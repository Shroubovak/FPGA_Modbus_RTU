module version
(
output wire [31:0] oHardwareVersion
 );
	assign oHardwareVersion = {8'd38, 8'd21, 8'd04, 8'd09};
endmodule
