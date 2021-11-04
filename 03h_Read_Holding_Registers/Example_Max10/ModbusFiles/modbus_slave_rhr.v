/*******************************************

	MODBUS READ HOLDING REGISTERS (03h)

********************************************/




module modbus_slave_rhr
(
//******************************************
//***** PINOUT
//******************************************

	input  clk,
	input  rst,	
	

//Serial port
	input  iRxd,
	output oTxd,	
	output oTxEn,

//Node ID
	input  [7:0] iNodeID,
		
//Input data (registers)
	input  [15:0] iData0,
	input  [15:0] iData1,
	input  [15:0] iData2,
	input  [15:0] iData3,
	input  [15:0] iData4,
	input  [15:0] iData5,
	input  [15:0] iData6,
	input  [15:0] iData7,
	input  [15:0] iData8,
	input  [15:0] iData9,
	input  [15:0] iDataA,
	input  [15:0] iDataB,
	input  [15:0] iDataC,
	input  [15:0] iDataD,
	input  [15:0] iDataE,
	input  [15:0] iDataF
	


);


//******************************************
//***** PARAMETERS
//******************************************
	parameter FCLK = 10000;						//[kHz]	max 50000 
	parameter BAUDE = 115200;					//bit/s	min 9600; max 1000000
	parameter RESPONSE_DELAY = 1000;			//[us]	max 300000
	parameter CRC_ENABLE = 1;



//******************************************
//***** VARIABLES
//******************************************
	reg  [2:0]  state = 0;
	reg  [2:0]  next_state = 0;
	reg  [15:0] DATA_RD = 0;
	wire [7:0]  DATA_RD_BYTE;
	reg  [15:0] checkAddrRd = 16'hFFFF;
	wire [15:0] addrRd;
	reg  [15:0] dataRd;
	reg  			cmdRegsRst = 0;
	reg 			TransmitEnable = 0;
	
//Request reciever
	wire [7:0] rxData;
	wire [3:0] rxByte; 
	wire rxAction;
	wire rxDataReady;
	wire rxCrcErr;

//Command registers
	reg  [7:0]  NODE_ID = 0;
	reg  [7:0]  FUNC = 0;
	reg  [15:0] START_ADDR = 0;
	reg  [7:0]  REGS_QNTY = 0;
	reg  [7:0]  EXCEP_CODE = 0;
	reg  STOP_REQUEST = 0;
	
//Error detection 
	reg [2:0] error = 0;
	

//Response transmitter 	
	reg  [7:0] txDataIn = 0;
	reg  [8:0] txByteQnty = 0;
	wire [7:0] txByte;  
	reg  txStart = 0;
	reg  [23:0] txStartCnt = 0;
	wire txStop;




//******************************************
//***** CONNECTION
//******************************************
	assign addrRd = (txByte > 8'd2) ? ((txByte - 8'd3) >> 1'b1) +  START_ADDR : 16'd0;
	assign DATA_RD_BYTE = txByte[0] ? DATA_RD[15:8] : DATA_RD[7:0];
	assign oTxEn = TransmitEnable;

	
	
//Latching data before reading	
	always @(posedge clk)
	begin
		if(rst)
		begin
			checkAddrRd <= 16'hFFFF;
		end
		else begin
			if(checkAddrRd != addrRd) 
			begin
				checkAddrRd <= addrRd;
				DATA_RD <= dataRd;
			end
		end
	end	




//******************************************
//***** REGISTERS TO READ
//******************************************
	always @*
	begin
		case(addrRd)
			16'd0 : dataRd = iData0;
			16'd1 : dataRd = iData1;
			16'd2 : dataRd = iData2;
			16'd3 : dataRd = iData3;
			16'd4 : dataRd = iData4;
			16'd5 : dataRd = iData5;
			16'd6 : dataRd = iData6;
			16'd7 : dataRd = iData7;
			16'd8 : dataRd = iData8;
			16'd9 : dataRd = iData9;
			16'd10: dataRd = iDataA;
			16'd11: dataRd = iDataB;
			16'd12: dataRd = iDataC;
			16'd13: dataRd = iDataD;
			16'd14: dataRd = iDataE;
			16'd15: dataRd = iDataF;

			 default: dataRd = 0;
		endcase	
	end






	
	
//******************************************
//*****MODBUS REQUEST
//******************************************	
//Request reciever
	aRx RXD
	(
		.clk(clk), 
		.rst(rst | cmdRegsRst), 
		.iRx(iRxd), 
		.oAction(rxAction), 
		.oDataOut(rxData), 
		.oDataReady(rxDataReady), 
		.oByteCnt(rxByte), 
		.oCrcErr(rxCrcErr)
	); 
	defparam RXD.FCLK = FCLK;
	defparam RXD.BRATE = BAUDE;
	defparam RXD.CRC_ENA = CRC_ENABLE;
	defparam RXD.WAIT_TIME = (50000000/BAUDE);
	defparam RXD.BUF_WIDTH = 4;
	
	

	
//Command registers
	always @(posedge cmdRegsRst or posedge rxDataReady)
	begin
		if(cmdRegsRst)
		begin
			NODE_ID 		 <= 0;
			FUNC 			 <= 0;
			START_ADDR 	 <= 0;
			REGS_QNTY 	 <= 0;
			STOP_REQUEST <= 0;
		end
		else begin
			if(rxByte == 0) NODE_ID <= rxData;
			if(rxByte == 1) FUNC <= rxData; 
			if(rxByte == 2) START_ADDR[15:8] <= rxData;
			if(rxByte == 3) START_ADDR[7:0]  <= rxData; 
			if(rxByte == 5) REGS_QNTY <= rxData;		 

			
			// stop request
			if(rxByte == 1) STOP_REQUEST <= (NODE_ID != iNodeID);
			
		end
	end

//Error detection					
	always @*
	begin
		if(rxCrcErr || (NODE_ID != iNodeID)) 
		
			error = 3'd1;	// no response

		else if((FUNC != 8'h03)) 
		
			error = 3'd2;	// Illegal Function
		
		else if((FUNC == 8'h03) && ((REGS_QNTY == 0) || (REGS_QNTY > 8'h7D)))
				 
			error = 3'd3;	// Illegal Data Value or Quantity of Registers
		
		else if((START_ADDR + REGS_QNTY) > 65534) 
		
			error = 3'd4;	// Illegal Starting Address + Quantity of Registers
			
//		else if()
//		
//			error = 3'd5;	// Slave Device Failure
//		
		else 
		
			error = 0;
	end		



//******************************************
//*****MODBUS RESPONSE
//******************************************	
	always @*
	begin
		if((error == 0))
		begin
			EXCEP_CODE = 0;
			
			if(FUNC == 8'h03)
			begin
				txByteQnty  = 9'h3 + (REGS_QNTY << 1);
				
				if		 (txByte == 0) txDataIn = NODE_ID;
				else if(txByte == 1)	txDataIn = FUNC;
				else if(txByte == 2)	txDataIn = REGS_QNTY << 1;
				else 						txDataIn = DATA_RD_BYTE;
			end
			
			else begin
				txDataIn = 0;
				txByteQnty = 0;
			end
		end
		
		else begin
			txByteQnty = 9'd3;
			
			if		 (txByte == 0)	txDataIn = iNodeID;
			else if(txByte == 1)	txDataIn = FUNC + 8'h80;
			else if(txByte == 2)	txDataIn = EXCEP_CODE;
			else 						txDataIn = 8'h00;	

			case(error)
						 2: EXCEP_CODE = 8'h01;	// Illegal Function
						 3: EXCEP_CODE = 8'h03;	// Illegal Data Value or Quantity of Registers
						 4: EXCEP_CODE = 8'h02;	// Illegal Starting Address + Quantity of Registers
				 default: EXCEP_CODE = 8'h04;	// Slave Device Failure 
			endcase
		end
	end


	
//Response transmitter 
	aTx TXD
	(
		.clk(clk), 
		.rst(rst), 
		.iStart(txStart), 
		.iDataIn(txDataIn), 
		.iNtxB(txByteQnty), 
		.oByteCnt(txByte), 
		.oTx(oTxd), 
		.oStop(txStop)
	);
	defparam TXD.FCLK = FCLK; 		
	defparam TXD.BRATE = BAUDE;	
	defparam TXD.CRC_ENA = CRC_ENABLE;
	defparam TXD.STOP_HOLD_TIME = (100000000/BAUDE);
	defparam TXD.BUF_WIDTH = 8;  		



		
//******************************************
//*****FSM
//******************************************			
		
	always @(posedge rst or posedge clk) 
	begin
		if(rst) state <= 0;
		else state <= next_state;
	end
	
	always @(*)
	begin
		case(state)
			0:		//Waiting for request
			begin
				if(rxAction) next_state = 1;
				else next_state = 0;
			end
			1:		//Request receiving 
			begin
				if(STOP_REQUEST) next_state = 5;
				else if(!rxAction) next_state = 2;
				else next_state = 1;
			end
			2:		//Errors case
			begin
				if(error == 1) next_state = 0;
				else if((FUNC == 8'h03) || (error > 1)) next_state = 3;
				else next_state = 0;
			end
			3:		//Waiting for transmitter to turn on
			begin
				if(txStartCnt >= (FCLK / 1000) * RESPONSE_DELAY) next_state = 4;
				else next_state = 3;
			end
			4:		//Response transmitting
			begin
				if(txStop) next_state = 5;
				else next_state = 4;
			end
			5:		//Process end
			begin
				if(!txStop) next_state = 0;
				else next_state = 5;
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
				txStart <= 0;
				cmdRegsRst <= 0;
				txStartCnt <= 0;
				TransmitEnable <= 0;
			end
//			1:
//			2:
			3:
			begin
				txStartCnt <= txStartCnt + 1'b1;
				TransmitEnable <= 1'b1;
			end
			4:
			begin
				txStart <= 1'b1;	
				txStartCnt <= 0;	
			end
			5:
			begin
				txStart <= 1'b0;
				cmdRegsRst <= 1'b1;
				TransmitEnable <= 0;
			end
	
		endcase
	end
	

endmodule
