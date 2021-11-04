


module Modbus_Top
(
//******************************************
//***** PINOUT
//******************************************
	input  iClk,									//pin N14	50 MHz 
	
	input  iBtnRst,								//pin M1

//Serial port										
	input  iRxd,									//pin AB15 PULL-UP
	output oTxd,									//pin AA15
	output oTxEn,									//pin Y16
	output onRxEn,									//pin AA14
	

//Leds	
	output oLedBlink,								//pin AA5, 
	output oLedRx,									//pin AB4, 
	output oLedTx									//pin T6
	            
	
);






//******************************************
//***** VARIABLES
//******************************************
	wire clk;
	wire rst;



//******************************************
//***** CONNECTION
//******************************************

//PLL
	pll MAIN_PLL (.inclk0(iClk), .c0(clk)); // c0 = 10 MHz

//LEDS
	assign oLedRx = iRxd;
	assign oLedTx = oTxd;
	assign oLedBlink = ~blink;

//RESET
	assign rst = ~iBtnRst;

//SERIAL PORT
	assign onRxEn = oTxEn;
	
	

//###################################################################################################################
//###################################################################################################################

//******************************************
//***** MODBUS SLAVE
//******************************************
	wire [15:0] modbusAddrRd;
	reg  [15:0] modbusDataRd;
	wire [15:0] modbusAddrWr;
	wire [15:0] modbusDataWr;
	wire 			modbusWrEn;


	modbus_slave MODBUS_SLAVE
	(
		.clk(clk),
		.rst(rst),
		
//Последовательный порт
		.iRxd(iRxd),
		.oTxd(oTxd),
		.oTxEn(oTxEn),
		
//Номер узла в сети 
		.iNodeID(8'h01),
		
//Чтение регистров 
		.oAddrRd(modbusAddrRd),
      .iDataRd(modbusDataRd),
		
//Запись в регистры 
		.oAddrWr(modbusAddrWr),
	   .oDataWr(modbusDataWr),
	   .oWrEn(modbusWrEn)   
		
	);
	defparam MODBUS_SLAVE.FCLK = 10000; 			//[kHz]	max 50000 
	defparam MODBUS_SLAVE.BAUDE = 115200;			//bit/s	min 9600; max 1000000
	defparam MODBUS_SLAVE.RESPONSE_DELAY = 2000;	//[us]	max 1300
	defparam MODBUS_SLAVE.CRC_ENABLE = 1;


//******************************************
//***** РЕГИСТРЫ ДЛЯ ЧТЕНИЯ
//******************************************
	always @*
	begin
		case(modbusAddrRd)
			16'h0000: modbusDataRd = hardwareVersion[31:16];
			16'h0001: modbusDataRd = hardwareVersion[15:0];
			16'h0002: modbusDataRd = test_reg_A;
			16'h0003: modbusDataRd = test_reg_B;
			16'h0004: modbusDataRd = secondsCnt;


			 default: modbusDataRd = 0;
		endcase	
	end

	
	
	
	
	
//******************************************
//***** РЕГИСТРЫ ДЛЯ ЗАПИСИ
//******************************************	
	
//0x0002
	wire [15:0] test_reg_A;

	holdingReg TEST_REG_A 
	(
		.clk(clk), 
		.rst(rst), 
		.ena(modbusWrEn & (modbusAddrWr == 16'h0002)), 
		.din(modbusDataWr), 
		.dout(test_reg_A)
	);	
	
	
//0x0003
	wire [15:0] test_reg_B;

	holdingReg TEST_REG_B 
	(
		.clk(clk), 
		.rst(rst), 
		.ena((modbusWrEn & (modbusAddrWr == 16'h0003))  | !flag), 
		.din(flag ? modbusDataWr : 16'h920E), 
		.dout(test_reg_B)
	);	

//0x0004
//см. ниже Счетчик секунд 	
	
	
//###################################################################################################################	
//###################################################################################################################
	
	
	
	
	
//******************************************
//***** КАКИЕ-ТО ДАННЫЕ (для примера)
//******************************************	
	
//Версия аппаратного обеспечения
	wire [31:0] hardwareVersion;									// Byte [     3		] [  2 ] [  1  ] [ 0 ]
	version VERSION (.oHardwareVersion(hardwareVersion)); //		  [Build Number] [Year] [Month] [Day]


	
//Счетчик секунд 
	reg  flag = 0;
	reg  [15:0] secondsCnt = 0; 
	reg  [31:0] tickCnt = 0;
	reg  blink = 0;
	
	always @(posedge rst or posedge clk)
	begin
		if(rst)
		begin
			secondsCnt <= 0;
			tickCnt <= 0;
			blink <= 0;
			flag <= 0;
		end
		else if(modbusWrEn & (modbusAddrWr == 16'h0004))
		begin
			secondsCnt <= modbusDataWr;
			tickCnt <= 0;
		end
		else begin
			if(tickCnt >= 10000000 - 1)
			begin
				secondsCnt <= secondsCnt + 1'b1;
				tickCnt <= 0;
				blink <= ~blink;
				flag <= 1'b1;
			end
			else begin
				tickCnt <= tickCnt + 1'b1;
			end
		end
	end
	
	
	
	
	
	
	

	
	
	
	
	

endmodule




























