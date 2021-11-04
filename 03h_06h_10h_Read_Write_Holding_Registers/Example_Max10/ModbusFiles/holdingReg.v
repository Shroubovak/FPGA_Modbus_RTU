module holdingReg (clk, rst, ena, din, dout);

	parameter WIDTH = 16;

	input [WIDTH-1:0] din; 
	input clk, rst, ena;
	output reg [WIDTH-1:0] dout =0;
	
	
	always @(posedge rst or posedge clk)
	begin
		if(rst) dout <= 0;
		else if(ena)  dout <= din;
	end

endmodule
