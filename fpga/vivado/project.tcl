# Create or update the Vivado project. Settings live in project.env at the repo root.
#   vivado -mode batch -source fpga/scripts/project.tcl            (create or sync)
#   vivado -mode batch -source fpga/scripts/project.tcl -tclargs clean   (recreate)

proc read_env {path} {
    set cfg [dict create]
    set fh [open $path r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} continue
        set eq [string first "=" $line]
        if {$eq < 0} continue
        set key [string trim [string range $line 0 [expr {$eq - 1}]]]
        set val [string trim [string range $line [expr {$eq + 1}] end]]
        dict set cfg $key $val
    }
    close $fh
    return $cfg
}

proc need {cfg key} {
    if {![dict exists $cfg $key]} { error "project.env is missing $key" }
    return [dict get $cfg $key]
}

proc find_files {dir patterns} {
    set result {}
    foreach p $patterns {
        set result [concat $result [glob -nocomplain -directory $dir -types f $p]]
    }
    foreach sub [glob -nocomplain -directory $dir -types d *] {
        set result [concat $result [find_files $sub $patterns]]
    }
    return $result
}

proc sync_fileset {fileset files} {
    set fs [get_filesets $fileset]
    set have {}
    foreach f [get_files -quiet -of_objects $fs] { lappend have [file normalize $f] }

    foreach f $files {
        set f [file normalize $f]
        if {[lsearch -exact $have $f] < 0} {
            add_files -norecurse -fileset $fs $f
            puts "  + $f"
        }
    }
    foreach f $have {
        if {![file exists $f]} {
            remove_files -fileset $fs $f
            puts "  - $f"
        }
    }
}

# --- Config ---
set repo_dir [file normalize [file join [file dirname [info script]] .. ..]]
set cfg      [read_env [file join $repo_dir project.env]]

set name      [need $cfg PROJ_NAME]
set part      [need $cfg PART]
set top       [need $cfg TOP]
set version   [need $cfg VIVADO_VERSION]
set rtl_dir   [file normalize [file join $repo_dir [need $cfg RTL_DIR]]]
set xdc_dir   [file normalize [file join $repo_dir [need $cfg XDC_DIR]]]
set tb_dir    [file normalize [file join $repo_dir [need $cfg TB_DIR]]]
set proj_dir  [file normalize [file join $repo_dir [need $cfg BUILD_DIR] vivado $name]]
set proj_file [file join $proj_dir $name.xpr]

if {![string match "$version*" [version -short]]} {
    error "This project needs Vivado $version, but you are running [version -short]."
}

# --- Open, create, or recreate ---
if {[info exists argv] && "clean" in $argv} {
    if {[current_project -quiet] ne ""} { close_project }
    file delete -force $proj_dir
}

if {[current_project -quiet] ne ""} {
    if {[file normalize [get_property DIRECTORY [current_project]]] ne $proj_dir} {
        error "A different project is open. Close it first."
    }
} elseif {[file exists $proj_file]} {
    open_project $proj_file
} else {
    create_project $name $proj_dir -part $part
    set_property target_language Verilog [current_project]
}

# --- Sync files ---
puts "Syncing files..."
sync_fileset sources_1 [find_files $rtl_dir {*.v *.vh}]
sync_fileset constrs_1 [find_files $xdc_dir {*.xdc}]
sync_fileset sim_1     [find_files $tb_dir  {*.v}]

foreach fs {sources_1 sim_1} {
    set_property include_dirs [list $rtl_dir] [get_filesets $fs]
}
set_property top $top [get_filesets sources_1]
update_compile_order -fileset sources_1

# --- Team-wide settings (the build folder isn't in git, so they go here) ---
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]

puts "Ready: $proj_file"