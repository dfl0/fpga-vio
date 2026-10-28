"""
IMU frame reader + live accel plot for FPGA UART stream (ICM-20948).

UART: 8N1 (1 start, 8 data, 1 stop)
Frame (112 data bits = 14 bytes):
    [0:2]   header 0xABCD
    [2:4]   accel_x  (int16, raw ADC)
    [4:6]   accel_y  (int16, raw ADC)
    [6:8]   accel_z  (int16, raw ADC)
    [8:10]  gyro_x   (int16, raw ADC)
    [10:12] gyro_y   (int16, raw ADC)
    [12:14] gyro_z   (int16, raw ADC)

Conversion (ICM-20948 datasheet DS-000189 v1.5, Tables 1 & 2, sections 8.19 / 8.25):
    accel [g]   = ACCEL_OUT / Accel_Sensitivity
    gyro  [dps] = GYRO_OUT  / Gyro_Sensitivity
Output is 16-bit two's complement; registers are read high byte first (XOUT_H, XOUT_L).

Requirements: pyserial, matplotlib
"""

import struct
import threading
import time
from collections import deque

import serial
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation

PORT = "COM7"
BAUD_RATE = 2_000_000

# --- Sensor configuration: MUST match what your FPGA writes to the ICM-20948 ---
# ACCEL_CONFIG (bank 2, 0x14) bits [2:1] ACCEL_FS_SEL
#   0: ±2 g  -> 16384 LSB/g     1: ±4 g  -> 8192 LSB/g
#   2: ±8 g  -> 4096 LSB/g      3: ±16 g -> 2048 LSB/g
ACCEL_FS_SEL = 0
# GYRO_CONFIG_1 (bank 2, 0x01) bits [2:1] GYRO_FS_SEL
#   0: ±250 dps -> 131 LSB/dps     1: ±500 dps  -> 65.5 LSB/dps
#   2: ±1000 dps -> 32.8 LSB/dps   3: ±2000 dps -> 16.4 LSB/dps
GYRO_FS_SEL = 0

ACCEL_SENSITIVITY = {0: 16384.0, 1: 8192.0, 2: 4096.0, 3: 2048.0}[ACCEL_FS_SEL]
GYRO_SENSITIVITY = {0: 131.0, 1: 65.5, 2: 32.8, 3: 16.4}[GYRO_FS_SEL]
ACCEL_RANGE_G = {0: 2, 1: 4, 2: 8, 3: 16}[ACCEL_FS_SEL]

# --- Protocol settings ---
BIG_ENDIAN = True          # ICM-20948 registers are high byte first; flip if your FPGA swaps them
PRINT_EVERY = 500          # Print every Nth frame to the console (0 = never)

# --- Plot settings ---
PLOT_WINDOW = 2000         # Number of most recent samples shown
PLOT_INTERVAL_MS = 50      # Plot refresh period (~20 FPS)
FIXED_Y_LIMITS = False     # True: y axis fixed to ±full-scale; False: autoscale

HEADER = 0xABCD
FRAME_SIZE = 14
_ENDIAN = ">" if BIG_ENDIAN else "<"
HEADER_BYTES = struct.pack(_ENDIAN + "H", HEADER)
FRAME_STRUCT = struct.Struct(_ENDIAN + "H6h")   # 6 signed int16 (two's complement)


def parse_frames(buf: bytearray, stats: dict):
    """Pull every complete, header-aligned frame out of buf (consumes bytes in place)."""
    frames = []
    while True:
        idx = buf.find(HEADER_BYTES)
        if idx < 0:
            # Keep the last byte in case it's the first half of a split header
            if len(buf) > 1:
                stats["skipped"] += len(buf) - 1
                del buf[:-1]
            break
        if idx > 0:
            stats["skipped"] += idx
            stats["resyncs"] += 1
            del buf[:idx]
        if len(buf) < FRAME_SIZE:
            break  # wait for the rest of the frame

        frames.append(FRAME_STRUCT.unpack_from(buf, 0)[1:])
        del buf[:FRAME_SIZE]
    return frames


def to_physical(raw):
    """Raw int16 ADC counts -> (ax, ay, az) in g and (gx, gy, gz) in dps."""
    ax, ay, az, gx, gy, gz = raw
    return (ax / ACCEL_SENSITIVITY, ay / ACCEL_SENSITIVITY, az / ACCEL_SENSITIVITY,
            gx / GYRO_SENSITIVITY, gy / GYRO_SENSITIVITY, gz / GYRO_SENSITIVITY)


class SerialReader(threading.Thread):
    """Reads the serial port in the background so the plot never stalls the UART."""

    def __init__(self):
        super().__init__(daemon=True)
        self.lock = threading.Lock()
        self.ax = deque(maxlen=PLOT_WINDOW)
        self.ay = deque(maxlen=PLOT_WINDOW)
        self.az = deque(maxlen=PLOT_WINDOW)
        self.stats = {"frames": 0, "skipped": 0, "resyncs": 0}
        self.error = None
        self.running = True
        self.rate_hz = 0.0

    def run(self):
        buf = bytearray()
        last_t, last_frames = time.perf_counter(), 0
        try:
            with serial.Serial(
                port=PORT,
                baudrate=BAUD_RATE,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.1,
            ) as ser:
                ser.reset_input_buffer()
                print(f"Listening on {PORT} at {BAUD_RATE} baud (8N1).")
                print(f"Accel ±{ACCEL_RANGE_G} g ({ACCEL_SENSITIVITY:g} LSB/g), "
                      f"Gyro FS_SEL={GYRO_FS_SEL} ({GYRO_SENSITIVITY:g} LSB/dps)")
                print(f"{'frame':>8} | {'ax[g]':>8} {'ay[g]':>8} {'az[g]':>8} | "
                      f"{'gx[dps]':>9} {'gy[dps]':>9} {'gz[dps]':>9}")
                print("-" * 76)

                while self.running:
                    chunk = ser.read(ser.in_waiting or 1)
                    if not chunk:
                        continue
                    buf.extend(chunk)
                    frames = parse_frames(buf, self.stats)
                    if not frames:
                        continue

                    with self.lock:
                        for raw in frames:
                            ax, ay, az, gx, gy, gz = to_physical(raw)
                            self.ax.append(ax)
                            self.ay.append(ay)
                            self.az.append(az)
                            self.stats["frames"] += 1
                            n = self.stats["frames"]
                            if PRINT_EVERY and n % PRINT_EVERY == 0:
                                print(f"{n:>8} | {ax:>8.4f} {ay:>8.4f} {az:>8.4f} | "
                                      f"{gx:>9.3f} {gy:>9.3f} {gz:>9.3f}")

                    now = time.perf_counter()
                    if now - last_t >= 1.0:
                        n = self.stats["frames"]
                        self.rate_hz = (n - last_frames) / (now - last_t)
                        last_t, last_frames = now, n

        except serial.SerialException as exc:
            self.error = exc
            print(f"Serial error: {exc}")
            print(f"Check that the device is connected, {PORT} is correct, "
                  "and no other program is using the port.")

    def snapshot(self):
        with self.lock:
            return list(self.ax), list(self.ay), list(self.az)


def main():
    reader = SerialReader()
    reader.start()

    fig, axis = plt.subplots(figsize=(10, 5))
    line_x, = axis.plot([], [], label="accel_x")
    line_y, = axis.plot([], [], label="accel_y")
    line_z, = axis.plot([], [], label="accel_z")
    axis.set_xlim(0, PLOT_WINDOW)
    axis.set_ylim(-ACCEL_RANGE_G, ACCEL_RANGE_G)
    axis.set_xlabel("Sample (most recent on the right)")
    axis.set_ylabel("Acceleration [g]")
    axis.grid(True, alpha=0.3)
    axis.legend(loc="upper left")
    title = axis.set_title("ICM-20948 accelerometer")

    def update(_):
        ax, ay, az = reader.snapshot()
        xs = range(len(ax))
        line_x.set_data(xs, ax)
        line_y.set_data(xs, ay)
        line_z.set_data(xs, az)
        if ax and not FIXED_Y_LIMITS:
            lo = min(min(ax), min(ay), min(az))
            hi = max(max(ax), max(ay), max(az))
            pad = max(0.05, 0.1 * (hi - lo))
            axis.set_ylim(lo - pad, hi + pad)
        s = reader.stats
        status = "SERIAL ERROR" if reader.error else f"{reader.rate_hz:,.0f} frames/s"
        title.set_text(f"ICM-20948 accelerometer (±{ACCEL_RANGE_G} g)  |  {status}  |  "
                       f"frames {s['frames']:,}  resyncs {s['resyncs']}")
        return line_x, line_y, line_z, title

    anim = FuncAnimation(fig, update, interval=PLOT_INTERVAL_MS, cache_frame_data=False)

    try:
        plt.show()   # close the window (or Ctrl+C) to stop
    except KeyboardInterrupt:
        pass
    finally:
        reader.running = False
        reader.join(timeout=1)
        s = reader.stats
        print(f"\nStopped. Frames: {s['frames']}  Resyncs: {s['resyncs']}  "
              f"Bytes skipped: {s['skipped']}")


if __name__ == "__main__":
    main()