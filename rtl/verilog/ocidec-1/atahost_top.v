/////////////////////////////////////////////////////////////////////
////                                                             ////
////  OCIDEC-1 ATA/ATAPI-5 Controller                            ////
////  Main Controller                                            ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2001, 2002 Richard Herveille                  ////
////                          richard@asics.ws                   ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////

//  CVS Log
//
//  $Id: atahost_top.v,v 1.6 2002-02-16 10:42:17 rherveille Exp $
//
//  $Date: 2002-02-16 10:42:17 $
//  $Revision: 1.6 $
//  $Author: rherveille $
//  $Locker:  $
//  $State: Exp $
//
// Change History:
//               rev.: 1.0    June 29th, 2001. Initial Verilog release
//               rev.: 1.1    July  3rd, 2001. Changed 'ADR_I[5:2]' into 'ADR_I' on output multiplexor sensitivity list.
//               rev.: 1.2    July  9th, 2001. Fixed register control; registers latched data on all edge cycles instead when selected.
//               rev.: 1.3    July 11th, 2001. Fixed case sensitivity error (nRESET instead of nReset) in "controller" module declaration.
//               rev.: 1.4    July 26th, 2001. Fixed non-blocking assignments.
//               rev.: 1.5  August 15th, 2001. Changed port-names to conform to new OpenCores naming-convention.
//               rev.: 1.6 October 15th, 2001. Removed ata_defines file. Changed define statement to parameter
//
//               $Log: not supported by cvs2svn $
//
//
//

/////////////////////////////////////////////////////////////
//
// DeviceType: OCIDEC-1: OpenCores IDE Controller type1
// Features: PIO Compatible Timing
// DeviceID: 0x01
// RevNo : 0x00
//

//
// Host signals:
// Reset
// DIOR-		read strobe. The falling edge enables data from device onto DD. The rising edge latches data at the host.
// DIOW-		write strobe. The rising edge latches data from DD into the device.
// DA(2:0)		3bit binary coded adress
// CS0-		select command block registers
// CS1-		select control block registers

`include "timescale.v"

module atahost_top (wb_clk_i, arst_i, wb_rst_i, wb_cyc_i, wb_stb_i, wb_ack_o, wb_err_o,
		wb_adr_i, wb_dat_i, wb_dat_o, wb_sel_i, wb_we_i, wb_inta_o,
		resetn_pad_o, dd_pad_i, dd_pad_o, dd_padoe_o, da_pad_o, cs0n_pad_o,
		cs1n_pad_o, diorn_pad_o, diown_pad_o, iordy_pad_i, intrq_pad_i);
	//
	// Parameter declarations
	//
	parameter ARST_LVL = 1'b0;                    // asynchronous reset level

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
	input wb_clk_i;                               // master clock in
	input arst_i;                                 // asynchronous reset
	input wb_rst_i;                               // synchronous reset

	// WISHBONE SLAVE signals
	input        wb_cyc_i;                        // valid bus cycle input
	input        wb_stb_i;                        // strobe/core select input
	output       wb_ack_o;                        // strobe acknowledge output
	output       wb_err_o;                        // error output
	input  [6:2] wb_adr_i;                        // A6 = '1' ATA devices selected
	                                              //          A5 = '1' CS1- asserted, '0' CS0- asserted
	                                              //          A4..A2 ATA address lines
	                                              // A6 = '0' ATA controller selected
	input  [31:0] wb_dat_i;                       // Databus in
	output [31:0] wb_dat_o;                       // Databus out
	input  [ 3:0] wb_sel_i;                       // Byte select signals
	input         wb_we_i;                        // Write enable input
	output        wb_inta_o;                      // interrupt request signal

	// ATA signals
	output        resetn_pad_o;
	input  [15:0] dd_pad_i;
	output [15:0] dd_pad_o;
	output        dd_padoe_o;
	output [ 2:0] da_pad_o;
	output        cs0n_pad_o;
	output        cs1n_pad_o;

	output        diorn_pad_o;
	output        diown_pad_o;
	input         iordy_pad_i;
	input         intrq_pad_i;

	//
	// constant declarations
	//
	parameter [3:0] DeviceId = 4'h1;
	parameter [3:0] RevisionNo = 4'h0;

	`define ATA_ATA_ADR wb_adr_i[6]
	`define ATA_CTRL_REG 4'b0000
	`define ATA_STAT_REG 4'b0001
	`define ATA_PIO_CMD 4'b0010

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

	// generate asynchronous reset level
	// arst_signal is either a wire or a NOT-gate
	wire arst_signal = arst_i ^ ARST_LVL;

	// generate bus cycle / address decoder
	wire w_acc  = &wb_sel_i[1:0];                        // word access
	wire dw_acc = &wb_sel_i;                             // double word access

	// bus error
	wire berr = `ATA_ATA_ADR ? !w_acc : !dw_acc;

	// PIO accesses at least 16bit wide
	wire PIOsel = wb_cyc_i & wb_stb_i & `ATA_ATA_ADR & w_acc;

	// CON accesses only 32bit wide
	wire CONsel = wb_cyc_i & wb_stb_i & !(`ATA_ATA_ADR) & dw_acc;

	// generate registers

	// generate register select signals
	wire sel_ctrl        = CONsel & wb_we_i & (wb_adr_i == `ATA_CTRL_REG);
	wire sel_stat        = CONsel & wb_we_i & (wb_adr_i == `ATA_STAT_REG);
	wire sel_PIO_cmdport = CONsel & wb_we_i & (wb_adr_i == `ATA_PIO_CMD);
	// reserved 0x03-0x0f --

	// generate control register
	always@(posedge wb_clk_i or negedge arst_signal)
		if (~arst_signal)
			begin
				CtrlReg[31:1] <= 0;
				CtrlReg[0] <= 1'b1; // set reset bit (ATA-RESETn line)
			end
		else if (wb_rst_i)
			begin
				CtrlReg[31:1] <= 0;
				CtrlReg[0] <= 1'b1; // set reset bit (ATA-RESETn line)
			end
		else if (sel_ctrl)
			CtrlReg <= wb_dat_i;

	// assign bits
	assign IDEctrl_IDEen       = CtrlReg[7];
	assign PIO_cmdport_IORDYen = CtrlReg[1];
	assign IDEctrl_rst         = CtrlReg[0];


	// generate status register clearable bits
	reg dirq, int;
	
	always@(posedge wb_clk_i or negedge arst_signal)
		if (~arst_signal)
			begin
				int  <= 1'b0;
				dirq <= 1'b0;
			end
		else if (wb_rst_i)
			begin
				int  <= 1'b0;
				dirq <= 1'b0;
			end
		else
			begin
				int  <= (int | (irq & !dirq)) & !(sel_stat & !wb_dat_i[0]);
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
	always@(posedge wb_clk_i or negedge arst_signal)
		if (~arst_signal)
			begin
				PIO_cmdport_T1   <= PIO_mode0_T1;
				PIO_cmdport_T2   <= PIO_mode0_T2;
				PIO_cmdport_T4   <= PIO_mode0_T4;
				PIO_cmdport_Teoc <= PIO_mode0_Teoc;
			end
		else if (wb_rst_i)
			begin
				PIO_cmdport_T1   <= PIO_mode0_T1;
				PIO_cmdport_T2   <= PIO_mode0_T2;
				PIO_cmdport_T4   <= PIO_mode0_T4;
				PIO_cmdport_Teoc <= PIO_mode0_Teoc;
			end
		else if(sel_PIO_cmdport)
			begin
				PIO_cmdport_T1   <= wb_dat_i[ 7: 0];
				PIO_cmdport_T2   <= wb_dat_i[15: 8];
				PIO_cmdport_T4   <= wb_dat_i[23:16];
				PIO_cmdport_Teoc <= wb_dat_i[31:24];
			end


	//
	// hookup controller section
	//
	atahost_controller #(TWIDTH, PIO_mode0_T1, PIO_mode0_T2, PIO_mode0_T4, PIO_mode0_Teoc)
		u1 (
			.clk(wb_clk_i),
			.nReset(arst_signal),
			.rst(wb_rst_i),
			.irq(irq),
			.IDEctrl_rst(IDEctrl_rst),
			.IDEctrl_IDEen(IDEctrl_IDEen),
			.PIO_cmdport_T1(PIO_cmdport_T1),
			.PIO_cmdport_T2(PIO_cmdport_T2),
			.PIO_cmdport_T4(PIO_cmdport_T4),
			.PIO_cmdport_Teoc(PIO_cmdport_Teoc),
			.PIO_cmdport_IORDYen(PIO_cmdport_IORDYen),
			.PIOreq(PIOsel),
			.PIOack(PIOack),
			.PIOa(wb_adr_i[5:2]),
			.PIOd(wb_dat_i[15:0]),
			.PIOq(PIOq),
			.PIOwe(wb_we_i),
			.RESETn(resetn_pad_o),
			.DDi(dd_pad_i),
			.DDo(dd_pad_o),
			.DDoe(dd_padoe_o),
			.DA(da_pad_o),
			.CS0n(cs0n_pad_o),
			.CS1n(cs1n_pad_o),
			.DIORn(diorn_pad_o),
			.DIOWn(diown_pad_o),
			.IORDY(iordy_pad_i),
			.INTRQ(intrq_pad_i)
		);

	//
	// generate WISHBONE interconnect signals
	//
	reg [31:0] Q;

	// generate acknowledge signal
	assign wb_ack_o = PIOack | CONsel;

	// generate error signal
	assign wb_err_o = wb_cyc_i & wb_stb_i & berr;

	// generate interrupt signal
	assign wb_inta_o = stat[0];
	
	// generate output multiplexor
	always@(wb_adr_i or CtrlReg or stat or PIO_cmdport_T1 or PIO_cmdport_T2 or PIO_cmdport_T4 or PIO_cmdport_Teoc)
		case (wb_adr_i[5:2]) // synopsis full_case parallel_case
			4'b0000: Q = CtrlReg;
			4'b0001: Q = stat;
			4'b0010: Q = {PIO_cmdport_Teoc, PIO_cmdport_T4, PIO_cmdport_T2, PIO_cmdport_T1};
			default: Q = 0;
		endcase

	// assign DAT_O output
	assign wb_dat_o = `ATA_ATA_ADR ? {16'h0000, PIOq} : Q;

endmodule




