set arg0 [lindex $quartus(args) 0]
set arg1 [lindex $quartus(args) 1]
set arg2 [lindex $quartus(args) 2]
post_message "###################################################################"
post_message "Generate build number"
post_message [format "Arguments: %s %s %s" $arg0 $arg1 $arg2]
#open file with build number and read line
set build_num_file [open "Version/build_number.txt" "r"]
fconfigure $build_num_file -buffering line
gets $build_num_file str
set var_build [expr $str]
if {$var_build >= 255} {
	set var_build 1
} else {
	incr var_build
}
close $build_num_file
#truncate file
close [open "Version/build_number.txt" "w"]
#write increased value of build number back into file
set build_num_file [open "Version/build_number.txt" "w"]
puts $build_num_file [format "%d" $var_build]
close $build_num_file
post_message [format "build number: %d" $var_build]
#get current date
set systemTime [clock seconds]
set year  [clock format $systemTime -format %y]
set month [clock format $systemTime -format %m]
set day   [clock format $systemTime -format %d]
#write Verilog file
set file [open "Version/version.v" w]
puts $file "module version"
puts $file "("
puts $file {output wire [31:0] oHardwareVersion}
puts $file " );"
puts $file "	assign oHardwareVersion = {8'd$var_build, 8'd$year, 8'd$month, 8'd$day};"
puts $file "endmodule"
close $file
post_message "###################################################################"