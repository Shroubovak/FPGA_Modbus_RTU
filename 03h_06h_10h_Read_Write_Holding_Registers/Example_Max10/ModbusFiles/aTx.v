/*******************************************
					UART TX DRIVER

*******************************************/

module aTx (clk, rst, iStart, iDataIn, iNtxB, oByteCnt, oTx, oStop);


	//-----PARAMETERS------------------------
	parameter FCLK = 10000; 					// [kHz] System clock frequency, max freq = 50000 kHz
	parameter BRATE = 115200;					// [baud] Baudrate, min brate = 9600 baud
	parameter STOP_HOLD_TIME = 50;			// [us] Stop signal hold time
	parameter BUF_WIDTH = 8;  					// Buffer size Width, Size = 2**BUF_WIDTH
//	parameter [BUF_WIDTH:0] iNtxB = 256;	// Byte quantity
	parameter CRC_ENA = 1;						// Enable crc calculation	
	parameter CRC_POLY = 16'hA001;			// Modbus standart crc polynom
	
	//-----I/O-------------------------------
	input  clk;
	input  rst;
	input  iStart;
	input  [7:0] iDataIn;
	input  [BUF_WIDTH:0] iNtxB;
	output reg [BUF_WIDTH-1:0] oByteCnt = 0;
	output reg oTx = 1;
	output reg oStop = 0;


	//-----VARIABLES-------------------------
	reg [2:0]  state = 0;
	reg [2:0]  next_state = 0;
	reg [7:0]  Tx_data = 0;
	reg [23:0] brateCnt = 0;	
	reg [3:0]  bitCnt = 0; 	
	reg [15:0] crc = 0;	
	reg [2:0]  crcFlag = 0;




	
	always @(posedge rst or posedge clk) 
	begin
		if(rst) 
		begin
			state <= 0;
		end
		else begin 
			if(iNtxB == 0) state <= 0;
			else state <= next_state;
		end
	end
	
	
	always @(*)
	begin
		case(state)
			0: 
			begin
				if(iStart) next_state = 1;
				else next_state = 0;
			end
			1: 
			begin
				next_state = 2;
			end
			2: 
			begin
				if(brateCnt >= (FCLK * 1000 / BRATE) - 1) next_state = 3;
				else next_state = 2;
			end
			3: 
			begin
				next_state = 4;
			end
			4: 
			begin
				if(bitCnt >= 9) next_state = 5;
				else next_state = 2;
			end
			5: 
			begin
				if(brateCnt >= (FCLK * 1000 / BRATE) - 1) next_state = 6;
				else next_state = 5;
			end
			6: 
			begin
				if((!CRC_ENA && crcFlag[0]) || (CRC_ENA && crcFlag[2])) next_state = 7;
				else next_state = 1;
			end
			7: 
			begin
				if(brateCnt > (FCLK * STOP_HOLD_TIME / 1000)) next_state = 0;
				else next_state = 7;
			end	
			default: next_state = 0;
		endcase
	end
	
	always @(negedge clk)
	begin
		case(state)		
			0: 		// Reset
			begin
				oTx <= 1'b1;
				brateCnt <= 0;
				bitCnt <= 0;
				oByteCnt <= 0;
				Tx_data <= 0;
				oStop <= 0;
				if(CRC_ENA)crc <= 16'hFFFF;
				crcFlag <= 0;
			end
			1:
			begin
				oTx <= 0;
				if(CRC_ENA)
				begin
					if(crcFlag[1]) 
					begin
						Tx_data <= crc[15:8];
					end
					else if(crcFlag[0]) 
					begin
						Tx_data <= crc[7:0]; 
					end
					else begin
						Tx_data <= iDataIn; 
						crc <= crc ^ {8'b0, iDataIn};
					end
				end
				else begin
					Tx_data <= iDataIn;
				end
			end
			2:
			begin
				brateCnt <= brateCnt + 1'b1;
			end
			3: 
			begin
				brateCnt <= 0;
				oTx <= Tx_data[0];
			end
			4:
			begin
				Tx_data[7] <= 1'b1;
				Tx_data[6:0] <= Tx_data [7:1];
				bitCnt <= bitCnt + 1'b1;
				if(CRC_ENA && (bitCnt > 0) && !crcFlag[0]) crc <= crc[0] ? {1'b0,crc[15:1]} ^ CRC_POLY : {1'b0,crc[15:1]};
			end
			5:
			begin
				bitCnt <= 0;
				oTx <= 1;
				brateCnt <= brateCnt + 1'b1;
			end
			6:
			begin
				brateCnt <= 0;	
				if(oByteCnt < iNtxB - 1)
				begin
					oByteCnt <= oByteCnt + 1'b1;
				end
				else begin
					crcFlag[0] <= 1'b1;
					crcFlag[2:1] <= crcFlag[1:0];
				end
			end
			7:
			begin
				brateCnt <= brateCnt + 1'b1;
				oStop <= 1;
			end

		endcase
	end


endmodule
























