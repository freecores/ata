//
// Project:		AT Atachement interface
// ATA-3 rev7B compliant
// Author:		Richard Herveille
// rev.: 1.0  June 29th, 2001. Initial Verilog release
// rev.: 1.1  July  3rd, 2001. Changed 'ADR_I[5:2]' into 'ADR_I' on output multiplexor sensitivity list.
// rev.: 1.2  July  9th, 2001. Fixed register control; registers latched data on all edge cycles instead when selected.
// rev.: 1.3  July 11th, 2001. Fixed case sensitivity error (nRESET instead of nReset) in "controller" module declaration.
// rev.: 1.4  July 26th, 2001. Fixed non-blocking assignments.

// DeviceType: OCIDEC-1: OpenCores IDE Controller type1
// Features: PIO Compatible Timing
// DeviceID: 0x01
// RevNo : 0x00

//
// Host signals:
// Reset
// DIOR-		read strobe. The falling edge enables data from device onto DD. The rising edge latches data at the host.
// DIOW-		write strobe. The rising edge latches data from DD into the device.
// DA(2:0)		3bit binary coded adress
// CS0-		select command block registers
// CS1-		select control block registers

`timescale 1ns / 10ps

module atahost (CLK_I, nReset, RST_I, CYC_I, STB_I, ACK_O, ERR_O, ADR_I, DAT_I, DAT_O, SEL_I, WE_I, INTA_O,
		RESETn, DDi, DDo, DDoe, DA, CS0n, CS1n, DIORn, DIOWn, IORDY, INTRQ);
	//
	// Parameter declarations
	//
	parameter TWIDTH = 8;                         // counter width
	// PIO mode 0 settings (@100MHz clock)
	parameter PIO_mode0_T1   =  6;                // 70ns
	parameter PIO_mode0_T2   = 28;                // 290ns
	parameter PIO_mode0_T4   =  2;                // 30ns
	parameter PIO_mode0_Teoc = 23;                // 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240

	//
	// inputs & outputs
	//

	// WISHBONE SYSCON signals
	input CLK_I;                                  // master clock in
	input nReset; //	= 1'b1;                          // asynchronous active low reset
	input RST_I; // = 1'b0;                           // synchronous active high reset

	// WISHBONE SLAVE signals
	input        CYC_I;                           // valid bus cycle input
	input        STB_I;                           // strobe/core select input
	output       ACK_O;                           // strobe acknowledge output
	output       ERR_O;                           // error output
	input  [6:2] ADR_I;                           // A6 = '1' ATA devices selected
	                                              //          A5 = '1' CS1- asserted, '0' CS0- asserted
	                                              //          A4..A2 ATA address lines
	                                              // A6 = '0' ATA controller selected
	input  [31:0] DAT_I; // Databus in
	output [31:0] DAT_O; // Databus out
	input  [ 3:0] SEL_I; // Byte select signals
	input         WE_I;  // Write enable input
	output        INTA_O; // interrupt request signal IDE0

	// ATA signals
	output RESETn;
	input  [15:0] DDi;
	output [15:0] DDo;
	output        DDoe;
	output [ 2:0] DA;
	output        CS0n;
	output        CS1n;

	output        DIORn;
	output        DIOWn;
	input         IORDY;
	input         INTRQ;

	//
	// constant declarations
	//
	parameter [3:0] DeviceId = 4'h1;
	parameter [3:0] RevisionNo = 4'h0;

	//
	// Variable declarations
	//

	// registers
	wire        IDEctrl_IDEen, IDEctrl_rst;
	reg  [ 7:0] PIO_cmdport_T1, PIO_cmdport_T2, PIO_cmdport_T4, PIO_cmdport_Teoc;
	wire        PIO_cmdport_IORDYen;
	reg  [31:0] CtrlReg; // control register

	wire        PIOack;
	wire [15:0] PIOq;

	wire [31:0] stat;

	wire irq; // ATA bus IRQ signal

	/////////////////
	// Module body //
	/////////////////

	// generate bus cycle / address decoder
	wire w_acc = SEL_I[1] & SEL_I[0];                        // word access
	wire dw_acc = SEL_I[3] & SEL_I[2] & SEL_I[1] & SEL_I[0]; // double word access

	// bus error
	wire berr = ADR_I[6] ? !w_acc : !dw_acc;

	// PIO accesses at least 16bit wide
	wire PIOsel = CYC_I & STB_I &  ADR_I[6] &  w_acc;

	// CON accesses only 32bit wide
	wire CONsel = CYC_I & STB_I & !ADR_I[6] & dw_acc;

	// generate registers

	// generate register select signals
	wire sel_ctrl        = CONsel & WE_I & !ADR_I[5] & !ADR_I[4] & !ADR_I[3] & !ADR_I[2]; // 0x00
	wire sel_stat        = CONsel & WE_I & !ADR_I[5] & !ADR_I[4] & !ADR_I[3] &  ADR_I[2]; // 0x01
	wire sel_PIO_cmdport = CONsel & WE_I & !ADR_I[5] & !ADR_I[4] &  ADR_I[3] & !ADR_I[2]; // 0x02
	// reserved 0x03-0x0f --

	// generate control register
	always@(posedge CLK_I or negedge nReset)
		if (~nReset)
			begin
				CtrlReg[31:1] <= 0;
				CtrlReg[0] <= 1'b1; // set reset bit (ATA-RESETn line)
			end
		else if (RST_I)
			begin
				CtrlReg[31:1] <= 0;
				CtrlReg[0] <= 1'b1; // set reset bit (ATA-RESETn line)
			end
		else if (sel_ctrl)
			CtrlReg <= DAT_I;

	// assign bits
	assign IDEctrl_IDEen       = CtrlReg[7];
	assign PIO_cmdport_IORDYen = CtrlReg[1];
	assign IDEctrl_rst         = CtrlReg[0];


	// generate status register clearable bits
	reg dirq, int;
	
	always@(posedge CLK_I or negedge nReset)
		if (~nReset)
			begin
				int  <= 1'b0;
				dirq <= 1'b0;
			end
		else if (RST_I)
			begin
				int  <= 1'b0;
				dirq <= 1'b0;
			end
		else
			begin
				int  <= (int | (irq & !dirq)) & !(sel_stat & !DAT_I[0]);
				dirq <= irq;
			end

	// assign status bits
	assign stat[31:28] = DeviceId;   // set Device ID
	assign stat[27:24] = RevisionNo; // set revision number
	assign stat[23: 1] = 0;          // --clear unused bits-- 
                                   // Although stat[7]=PIOtip this bit is zero, because it is impossible 
                                   // to read the status register and access the PIO registers at the same time.
	assign stat[0]     = int;


	// generate PIO compatible / command-port timing register
	always@(posedge CLK_I or negedge nReset)
		if (~nReset)
			begin
				PIO_cmdport_T1   <= PIO_mode0_T1;
				PIO_cmdport_T2   <= PIO_mode0_T2;
				PIO_cmdport_T4   <= PIO_mode0_T4;
				PIO_cmdport_Teoc <= PIO_mode0_Teoc;
			end
		else if (RST_I)
			begin
				PIO_cmdport_T1   <= PIO_mode0_T1;
				PIO_cmdport_T2   <= PIO_mode0_T2;
				PIO_cmdport_T4   <= PIO_mode0_T4;
				PIO_cmdport_Teoc <= PIO_mode0_Teoc;
			end
		else if(sel_PIO_cmdport)
			begin
				PIO_cmdport_T1   <= DAT_I[ 7: 0];
				PIO_cmdport_T2   <= DAT_I[15: 8];
				PIO_cmdport_T4   <= DAT_I[23:16];
				PIO_cmdport_Teoc <= DAT_I[31:24];
			end


	//
	// hookup controller section
	//
	controller #(TWIDTH, PIO_mode0_T1, PIO_mode0_T2, PIO_mode0_T4, PIO_mode0_Teoc)
		u1 (CLK_I, nReset, RST_I, irq, IDEctrl_rst,	IDEctrl_IDEen, PIO_cmdport_T1, PIO_cmdport_T2, PIO_cmdport_T4, PIO_cmdport_Teoc, PIO_cmdport_IORDYen, 
			PIOsel, PIOack, ADR_I[5:2], DAT_I[15:0], PIOq, WE_I, RESETn, DDi, DDo, DDoe, DA, CS0n, CS1n, DIORn, DIOWn, IORDY, INTRQ);

	//
	// generate WISHBONE interconnect signals
	//
	reg [31:0] Q;

	// generate acknowledge signal
	assign ACK_O = PIOack | CONsel;

	// generate error signal
	assign ERR_O = CYC_I & STB_I & berr;

	// generate interrupt signal
	assign INTA_O = stat[0];
	
	// generate output multiplexor
	always@(ADR_I or CtrlReg or stat or PIO_cmdport_T1 or PIO_cmdport_T2 or PIO_cmdport_T4 or PIO_cmdport_Teoc)
		case (ADR_I[5:2])
			4'b0000: Q = CtrlReg;
			4'b0001: Q = stat;
			4'b0010: Q = {PIO_cmdport_Teoc, PIO_cmdport_T4, PIO_cmdport_T2, PIO_cmdport_T1};
			default: Q = 0;
		endcase

	// assign DAT_O output
	assign DAT_O = ADR_I[6] ? {16'h0000, PIOq} : Q;
endmodule


