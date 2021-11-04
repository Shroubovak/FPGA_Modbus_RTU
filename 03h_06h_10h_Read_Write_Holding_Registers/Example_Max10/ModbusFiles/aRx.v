/************************************************
							UART RX

************************************************/
module aRx(clk, rst, iRx, oAction, oDataOut, oDataReady, oByteCnt, oCrcErr); 

	//----- PARAMETERS ----------------------
	parameter FCLK = 50000; 			// [kHz]  System clock frequency, max freq = 80000 kHz
	parameter BRATE = 115200;			// [baud] Baudrate, min brate = 9600 baud
	parameter WAIT_TIME = 50;			// [us] 	 Data waiting time before reset
	parameter BUF_WIDTH = 8;  			// Buffer size Width, Size = 2**BUF_WIDTH
	parameter CRC_ENA = 1;				// Enable crc calculation
	parameter CRC_POLY = 16'hA001;	// Modbus standart crc polynom
	
	
	//----- PINOUT ---------------------------
	input clk;
	input rst;
	input iRx;
	
	
	output oAction;
	output [7:0] oDataOut;	
	output reg oDataReady = 0;
	output reg [BUF_WIDTH-1:0] oByteCnt = 0;
	output reg oCrcErr = 0;

	
	//----- VARIABLES -----------------------  
	reg  [2:0] state = 0;
	reg  [2:0] next_state =0;
	wire byteCntRst;
	reg  [9:0] shdata = {10'h3FF};
	reg  [7:0] previousByte = 8'hFF; 
	reg  [23:0] cnt = 0;
	reg  [3:0] bcnt = 0;
	reg  rxd = 0;
	reg  rxd_i = 0;
	reg  action = 0;
	reg  action_i = 0;
	reg  [15:0] crc = 16'hFFFF;
	reg  [15:0] crcOut = 16'hFFFF;

	

	//----- Connections -----
	assign oDataOut = shdata[8:1];
	assign oAction = action | action_i;
	always @(negedge clk) begin action_i <= action; end
		
	//----- Synchronize ------ 
	always @(posedge clk)
	begin
		rxd_i <= iRx;
		rxd <= rxd_i;
	end
	
	//----- CRC error latch -----
	generate
	if(CRC_ENA)
	begin: crcerr_on
		always @(posedge rst or negedge action)
		begin
			if(rst) oCrcErr <= 0;
			else oCrcErr <= (crcOut != {shdata[8:1], previousByte});
		end
	end
	else begin: crcerr_off
		always @*
		begin
			oCrcErr <= ~(&crcOut & &crc & &previousByte);
		end
	end
	endgenerate
	
	//----- Byte counter -----
	assign byteCntRst = ~action & (state == 3);
	
	always @(posedge rst or posedge byteCntRst or negedge oDataReady)
	begin
		if(rst) oByteCnt <= 0;
		else if(byteCntRst) oByteCnt <= 0;
		else oByteCnt <= oByteCnt + 1'b1;
	end

	//----- FSM -----
	always @(posedge rst or posedge clk) 
	begin
		if(rst) state <= 0;
		else state <= next_state;
	end
	
	always @(*)
	begin
		case(state)
			0:
			begin
				next_state = 1;
			end
			1:
			begin
				if(cnt > (FCLK * WAIT_TIME / 1000)) next_state = 0; 				
				else if(!rxd) next_state = 2;
				else next_state = 1;
			end	
			2:
			begin
				next_state = 3;
			end
			3:
			begin
				if(rxd) next_state = 1;
				else if(cnt >= (FCLK * 500 / BRATE)) next_state = 4;
				else next_state = 3;
			end
			4:
			begin
				next_state = 5;
			end
			5:
			begin
				if(bcnt > 9) next_state = 7;
				else next_state = 6;
			end
			6:
			begin
				if(cnt >= (FCLK * 1000 / BRATE)) next_state = 5; 
				else next_state = 6;
			end
			7:
			begin
				next_state = 1;
			end
			default: next_state = 0;
		endcase
	end	
	
	
	//----- State handler -----
	always @(negedge clk)
	begin
		case(state)		
			0:
			begin
				oDataReady <= 0;
				cnt <= 0;
				action <= 0;
				if(CRC_ENA)crc <= 16'hFFFF;
			end
			1:
			begin
				if(action)cnt <= cnt + 1'b1;	
				oDataReady <= 0;
			end
			2:
			begin
				cnt <= 0;
			end
			3:
			begin
				cnt <= cnt + 1'b1;
			end
			4:
			begin
				if(CRC_ENA)
				begin
					if(oByteCnt > 0)crc <= crc ^ {8'b0, shdata[8:1]};
					previousByte <= shdata[8:1];
					crcOut  <= crc;
				end
			end
			5:
			begin
				action <= 1'b1;
				cnt <= 0;
				bcnt <= bcnt + 1'b1;
				shdata[9] <= rxd;
				shdata[8:0] <= shdata [9:1];
				if(CRC_ENA)
				begin
					if((oByteCnt > 0) && !bcnt[3])crc <= crc[0] ? {1'b0,crc[15:1]} ^ CRC_POLY : {1'b0,crc[15:1]};
				end
			end
			6:
			begin
				cnt <= cnt + 1'b1;
			end
			7:
			begin
				cnt <= 0;
				bcnt <= 0;
				if(!oByteCnt[BUF_WIDTH-1]) oDataReady <= 1'b1;
			end
		endcase
	end


	
endmodule


