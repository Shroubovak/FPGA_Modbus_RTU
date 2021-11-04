

module modbus_slave
(
//******************************************
//***** PINOUT
//******************************************

	input  clk,
	input  rst,	
	

//Последовательный порт
	input  iRxd,
	output oTxd,
	output oTxEn,	

//Номер узла в сети 
	input  [7:0]  iNodeID,
		
//Чтение регистров 
	output [15:0] oAddrRd,
	input  [15:0] iDataRd,
	

//Запись в регистры 
	output [15:0] oAddrWr,
	output [15:0] oDataWr,
	output 		  oWrEn   
	

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
	reg  [3:0]  state = 0;
	reg  [3:0]  next_state = 0;
	reg 			TransmitEnable = 0;
	reg  [15:0] checkAddrRd = 16'hFFFF;
	reg  [15:0] DATA_RD = 0;
	wire [7:0]  DATA_RD_BYTE;
	reg  			cmdRegsRst = 0;
	reg  			dataWrReady = 0; 
	reg  [15:0] dataWrBuf = 0;
	wire [15:0] addrWr;
	wire [15:0] dataWr;


	
//Request reciever
	wire [7:0] rxData;
	wire [8:0] rxByte; 
	wire rxAction;
	wire rxDataReady;
	wire rxCrcErr;

//Command registers
	reg  [7:0]  NODE_ID = 0;
	reg  [7:0]  FUNC = 0;
	reg  [15:0] START_ADDR = 0;
	reg  [15:0] REG_VAL = 0;
	reg  [7:0]  REGS_QNTY = 0;
	reg  [7:0]  BYTE_COUNT = 0;
	reg  [7:0]  EXCEP_CODE = 0;
	reg  STOP_REQUEST = 0;
	
//Error detection 
	reg [2:0] error = 0;
	
//Request buffer
	wire [7:0] bufRxDataOut;
	reg  [8:0] bufRxWrAddr = 0;
	reg  [7:0] bufRxRdAddr = 0;
	wire bufRxWrEn;	

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
	assign oAddrRd = (txByte > 8'd2) ? ((txByte - 8'd3) >> 1'b1) +  START_ADDR : 16'd0;
	assign DATA_RD_BYTE = txByte[0] ? DATA_RD[15:8] : DATA_RD[7:0];
	assign oAddrWr = START_ADDR + (bufRxRdAddr >> 1) - 1'b1;	
	assign oDataWr = dataWrBuf;
	assign oWrEn = dataWrReady;
	assign oTxEn = TransmitEnable;
	
	
//Защелкивание данных перед считыванием	
	always @(posedge clk)
	begin
		if(rst)
		begin
			checkAddrRd <= 16'hFFFF;
		end
		else begin
			if(checkAddrRd != oAddrRd) 
			begin
				checkAddrRd <= oAddrRd;
				DATA_RD <= iDataRd;
			end
		end
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
	defparam RXD.BUF_WIDTH = 9;
	
	

	
//Command registers
	always @(posedge cmdRegsRst or posedge rxDataReady)
	begin
		if(cmdRegsRst)
		begin
			NODE_ID 		 <= 0;
			FUNC 			 <= 0;
			START_ADDR 	 <= 0;
			REG_VAL 		 <= 0;
			REGS_QNTY 	 <= 0;
			BYTE_COUNT 	 <= 0;
			STOP_REQUEST <= 0;
		end
		else begin
			if(rxByte == 0) NODE_ID <= rxData;
			if(rxByte == 1) FUNC <= rxData; 
			if(rxByte == 2) START_ADDR[15:8] <= rxData;
			if(rxByte == 3) START_ADDR[7:0]  <= rxData; 
			if(rxByte == 4) REG_VAL[15:8] <= rxData;	 // FUNC = 06h
			if(rxByte == 5) REG_VAL[7:0] <= rxData;	 // FUNC = 06h
			if(rxByte == 5) REGS_QNTY <= rxData;		 // FUNC = 03h, 10h 
			if(rxByte == 6) BYTE_COUNT <= rxData;		 // FUNC = 10h
			
			// stop request
			if(rxByte == 1) STOP_REQUEST <= (NODE_ID != iNodeID);
			
		end
	end

//Error detection					
	always @*
	begin
		if(rxCrcErr || (NODE_ID != iNodeID)) 
		
			error = 3'd1;	// no response

		else if((FUNC != 8'h03) && (FUNC != 8'h06) && (FUNC != 8'h10)) 
		
			error = 3'd2;	// Illegal Function
		
		else if(((FUNC == 8'h03) && ((REGS_QNTY == 0) || (REGS_QNTY > 8'h7D))) || ((FUNC == 8'h10) && ((REGS_QNTY == 0) || (REGS_QNTY > 8'h7B)   || BYTE_COUNT != (REGS_QNTY << 1))))
				 
			error = 3'd3;	// Illegal Data Value or Quantity of Registers
		
		else if(((START_ADDR + REGS_QNTY) > 65534) && (FUNC != 8'h06)) 
		
			error = 3'd4;	// Illegal Starting Address + Quantity of Registers
			
//		else if()
//		
//			error = 3'd5;	// Slave Device Failure
//		
		else 
		
			error = 0;
	end		

	
//Request buffer for FUNC = 06h or FUNC = 10h
	rxBuffer BUF_RX
	(
		.clock(clk), 
		.data(rxData),  
		.wraddress(bufRxWrAddr[7:0]), 
		.wren(bufRxWrEn), 
		.rdaddress(bufRxRdAddr),
		.q(bufRxDataOut)
	);

//bufRxWrAddr
	always @*
	begin
		if		 (FUNC == 8'h06) bufRxWrAddr = rxByte > 9'd3 ? rxByte - 9'd4 : 9'd0;
		else if(FUNC == 8'h10) bufRxWrAddr = rxByte > 9'd6 ? rxByte - 9'd7 : 9'd0;
		else 						  bufRxWrAddr = 0;
	end
	
//bufRxWrEn
	assign bufRxWrEn = rxDataReady & ((FUNC == 8'h06) | (FUNC == 8'h10));



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
			else if(FUNC == 8'h06)
			begin
				txByteQnty = 9'd6;
				
				if		 (txByte == 0)	txDataIn = NODE_ID;
				else if(txByte == 1)	txDataIn = FUNC;
				else if(txByte == 2)	txDataIn = START_ADDR[15:8];
				else if(txByte == 3)	txDataIn = START_ADDR[7:0];
				else if(txByte == 4)	txDataIn = REG_VAL[15:8];
				else if(txByte == 5)	txDataIn = REG_VAL[7:0];
				else 						txDataIn = 8'h00;		
			end
			else if(FUNC == 8'h10)
			begin
				txByteQnty = 9'd6;
				
				if		 (txByte == 0)	txDataIn = NODE_ID;
				else if(txByte == 1)	txDataIn = FUNC;
				else if(txByte == 2)	txDataIn = START_ADDR[15:8];
				else if(txByte == 3)	txDataIn = START_ADDR[7:0];
				else if(txByte == 4)	txDataIn = 8'h00;
				else if(txByte == 5)	txDataIn = REGS_QNTY;
				else 						txDataIn = 8'h00;
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
			0:
			begin
				if(rxAction) next_state = 1;
				else next_state = 0;
			end
			1:
			begin
				if(STOP_REQUEST) next_state = 5;
				else if(!rxAction) next_state = 2;
				else next_state = 1;
			end
			2:
			begin
				if(error == 1) next_state = 0;
				else if((FUNC == 8'h03) || (error > 1)) next_state = 3;
				else if((FUNC == 8'h06) || (FUNC == 8'h10)) next_state = 6;
				else next_state = 0;
			end
			3:
			begin
				if(txStartCnt >= (FCLK / 1000) * RESPONSE_DELAY) next_state = 4;
				else next_state = 3;
			end
			4:
			begin
				if(txStop) next_state = 5;
				else next_state = 4;
			end
			5:
			begin
				if(!txStop) next_state = 0;
				else next_state = 5;
			end
			6:	next_state = 7;
			7:	next_state = 8;
			8:	next_state = 9;
			9:
			begin
				if(FUNC == 8'h06) next_state = 3;
				else if(FUNC == 8'h10) next_state = 10;
				else next_state = 0;
			end
			10:
			begin
				if(bufRxRdAddr >= (REGS_QNTY << 1)) next_state = 3;
				else next_state = 6;
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
				bufRxRdAddr <= 0;
				dataWrReady <= 0;
				txStartCnt <= 0;
				TransmitEnable <= 0;
			end
//			1:
//			2:
			3:
			begin
				TransmitEnable <= 1'b1;
				txStartCnt <= txStartCnt + 1'b1;
				dataWrReady = 0;
			end
			4:
			begin
				txStart <= 1'b1;	
				txStartCnt <= 0;	
			end
			5:
			begin
				TransmitEnable <= 0;
				txStart <= 1'b0;
				cmdRegsRst <= 1'b1;
			end
			6:
			begin
				dataWrBuf[15:8] <= bufRxDataOut;
				bufRxRdAddr <= bufRxRdAddr + 1'b1;
			end
			7:
			begin
				dataWrBuf[7:0] <= bufRxDataOut;
				bufRxRdAddr <= bufRxRdAddr + 1'b1;
			end
			8:
			begin
				dataWrReady <= 1'b1;
			end
//			9:
			10:
			begin
				dataWrReady <= 0;
			end
	
		endcase
	end
	
	
	


endmodule













