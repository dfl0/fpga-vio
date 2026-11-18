#include <algorithm>
#include <array>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <optional>
#include <iostream>
#include <stdexcept>
#include <system_error>
#include <vector>

#include <fcntl.h>
#include <termios.h>
#include <unistd.h>

#include "stream_writer.hpp"

namespace {

constexpr std::array<uint8_t, 2> sync_bytes{0xab, 0xcd};
constexpr size_t packet_size = 2 + 8 + 12 + 128;

void serialError(const char* operation) {
    throw std::system_error(errno, std::generic_category(), operation);
}

void configureSerial(int fd) {
#ifdef B2000000
    termios options{};
    if (tcgetattr(fd, &options) < 0) serialError("read serial settings");
    cfmakeraw(&options);
    options.c_cflag &= ~(CSIZE | CSTOPB | PARENB | CRTSCTS);
    options.c_cflag |= CS8 | CLOCAL | CREAD;
    options.c_cc[VMIN] = 1;
    options.c_cc[VTIME] = 0;
    if (cfsetispeed(&options, B2000000) < 0 || cfsetospeed(&options, B2000000) < 0 ||
        tcsetattr(fd, TCSANOW, &options) < 0) serialError("set serial settings");
    if (tcflush(fd, TCIFLUSH) < 0) serialError("flush serial input");
#else
    (void)fd;
    throw std::runtime_error("Live UART requires termios support for 2000000 baud; use --capture for replay");
#endif
}

int signedWord(const uint8_t* bytes) {
    const int word = bytes[0] * 256 + bytes[1];
    return word < 32768 ? word : word - 65536;
}

mapping::StreamEvent decodeImu(const uint8_t* bytes, uint64_t time_us) {
    mapping::StreamEvent event{};
    event.kind = mapping::StreamEvent::Kind::Imu;
    auto& sample = event.imu;
    sample.time = time_us * 1e-6;
    for (int i = 0; i < 3; ++i) {
        sample.acceleration[i] = signedWord(bytes + 10 + 2 * i) * (9.80665 / 16384);
        sample.angular_velocity[i] = signedWord(bytes + 16 + 2 * i) * (CV_PI / (180 * 131));
    }
    return event;
}

void readPackets(int fd, bool capture) {
    std::optional<uint64_t> last_time;
    std::vector<uint8_t> buffer;
    bool locked = false;
    uint8_t chunk[4096];
    for (;;) {
        const ssize_t n = read(fd, chunk, sizeof(chunk));
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) serialError("read UART");
        if (!n) {
            if (!capture) throw std::runtime_error("Serial device disconnected");
            if (!locked || !buffer.empty())
                throw std::runtime_error("Incomplete or unrecognized UART capture");
            return;
        }
        buffer.insert(buffer.end(), chunk, chunk + n);
        while (buffer.size() >= packet_size) {
            if (!locked) {
                auto marker = std::search(buffer.begin(), buffer.end(),
                                          sync_bytes.begin(), sync_bytes.end());
                if (marker == buffer.end() && buffer.back() == sync_bytes[0]) --marker;
                buffer.erase(buffer.begin(), marker);
                if (buffer.size() < packet_size + sync_bytes.size()) break;
                if (!std::equal(sync_bytes.begin(), sync_bytes.end(), buffer.begin() + packet_size)) {
                    buffer.erase(buffer.begin());
                    continue;
                }
                locked = true;
            }
            if (!std::equal(sync_bytes.begin(), sync_bytes.end(), buffer.begin())) {
                throw std::runtime_error("Lost UART packet alignment; restart the bridge");
            }
            uint64_t time = 0;
            for (int i = 2; i < 10; ++i) time = (time << 8) | buffer[i];
            if (last_time && time <= *last_time)
                throw std::runtime_error("FPGA timestamp did not advance; restart after an FPGA reset");
            last_time = time;
            if (!writeStreamEvent(std::cout, decodeImu(buffer.data(), time)) || !std::cout.flush())
                throw std::runtime_error("Cannot write mapper stream");
            buffer.erase(buffer.begin(), buffer.begin() + packet_size);
        }
    }
}

}  // namespace

int main(int argc, char** argv) {
    const bool capture = argc == 3 && std::string(argv[1]) == "--capture";
    if (argc != 2 && !capture) {
        std::cerr << "Usage: uart_bridge DEVICE | uart_bridge --capture FILE\n";
        return 1;
    }
    try {
        const int fd = open(argv[capture ? 2 : 1], O_RDONLY | O_NOCTTY);
        if (fd < 0) serialError("open UART input");
        if (!capture) configureSerial(fd);
        if (!writeImuStreamHeader(std::cout) || !std::cout.flush())
            throw std::runtime_error("Cannot write mapper stream header");
        readPackets(fd, capture);
        close(fd);
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
