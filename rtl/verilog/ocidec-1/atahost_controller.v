//
// file: controller.v
//	description: OCIDEC1 OpenCores IDE controller type-1
// author : Richard Herveille
// rev.: 1.0  june  28th, 2001. Initial Verilog release
// rev.: 1.1  July   3rd, 2001. Rewrote "IORDY" and "INTRQ" capture section.
// rev.: 1.2  July   9th, 2001. Added "timescale". Undid "IORDY & INTRQ" rewrite.
// rev.: 1.3  July  11th, 2001. Changed PIOreq & PIOack generation (made them synchronous). 
// rev.: 1.4  July  26th, 2001. Fixed non-blocking assignments.

// OCIDEC1 supports:	
// -Common Compatible timing access to all connected devices
//

`include "timescale.v"

module atahost_controller (clk, nReset, rst, irq, IDEctrl_rst, IDEctrl_IDEen, 
			PIO_cmdport_T1, PIO_cmdport_T2, PIO_cmdport_T4, PIO_cmdport_Teoc, PIO_cmdport_IORDYen, 
			PIOreq, PIOack, PIOa, PIOd, PIOq, PIOwe, 
			RESETn, DDi, DDo, DDoe, DA, CS0n, CS1n, DIORn, DIOWn, IORDY, INTRQ);
	//
	// parameter declarations
	//
	parameter TWIDTH = 8;              // counter width
	// PIO mode 0 timing settings @100MHz master clock
	parameter PIO_mode0_T1   = 6;      // 70ns
	parameter PIO_mode0_T2   = 28;     // 290ns
	parameter PIO_mode0_T4   = 2;      // 30ns
	parameter PIO_mode0_Teoc = 23;     // 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240
	//
	// inputs & outputs
	//
	input  clk; //master clock
	input  nReset; // asynchronous active low reset
	input  rst; // synchronous active high reset
	
	output irq; // interrupt request signal
	reg irq;
	
	// control bits
	input  IDEctrl_rst;
	input  IDEctrl_IDEen;

	// PIO timing registers
	input  [7:0] PIO_cmdport_T1;
	input  [7:0] PIO_cmdport_T2;
	input  [7:0] PIO_cmdport_T4;
	input  [7:0] PIO_cmdport_Teoc;
	input        PIO_cmdport_IORDYen;

	// PIO control signals
	input         PIOreq; // PIO transfer request
	output        PIOack; // PIO transfer ended
	input  [ 3:0] PIOa;   // PIO address
	input  [15:0] PIOd;   // PIO data in
	output [15:0] PIOq;   // PIO data out
	input         PIOwe;  // PIO direction  bit. 1'b1==write, 1'b0==read

	reg [15:0] PIOq;
	reg PIOack;

	// ATA signals
	output        RESETn;
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

	reg        RESETn;
	reg [15:0] DDo;
	reg        DDoe;
	reg [ 2:0] DA;
	reg        CS0n;
	reg        CS1n;
	reg        DIORn;
	reg        DIOWn;

	//
	// Variable declarations
	//

	reg dPIOreq;
	reg PIOgo;   // start PIO timing controller
	wire PIOdone; // PIO timing controller done

	// PIO signals
	wire PIOdior, PIOdiow;
	wire PIOoe;

	// Timing settings
	wire              dstrb;
	wire [TWIDTH-1:0] T1, T2, T4, Teoc;
	wire              IORDYen;

	// synchronized ATA inputs
	reg sIORDY;

	//
	// Module body
	//


	// synchronize incoming signals
	reg cIORDY;                               // capture IORDY
	reg cINTRQ;                               // capture INTRQ

	always@(posedge clk)
	begin : synch_incoming

		cIORDY <= IORDY;
		cINTRQ <= INTRQ;

		sIORDY <= cIORDY;
		irq <= cINTRQ;
	end

	// generate ATA signals
	always@(posedge clk or negedge nReset)
		if (~nReset)
			begin
				RESETn <= 1'b0;
				DIORn  <= 1'b1;
				DIOWn  <= 1'b1;
				DA     <= 0;  // ????
				CS0n	  <= 1'b1;
				CS1n	  <= 1'b1;
				DDo    <= 0;
				DDoe   <= 1'b0;
			end
		else if (rst)
			begin
				RESETn <= 1'b0;
				DIORn  <= 1'b1;
				DIOWn  <= 1'b1;
				DA     <= 0;  // ????
				CS0n	  <= 1'b1;
				CS1n	  <= 1'b1;
				DDo    <= 0;
				DDoe   <= 1'b0;
			end
		else
			begin
				RESETn <= !IDEctrl_rst;
				DA     <= PIOa[2:0];
				CS0n	  <= !( !PIOa[3] & PIOreq); // CS0 asserted when A(3) = '0'
				CS1n	  <= !(  PIOa[3] & PIOreq); // CS1 asserted when A(3) = '1'

				DDo    <= PIOd;
				DDoe   <= PIOoe;
				DIORn  <= !PIOdior;
				DIOWn  <= !PIOdiow;
			end


	//
	//////////////////////////
	// PIO transfer control //
	//////////////////////////
	//
	// capture ATA data for PIO access
	always@(posedge clk)
		if (dstrb)
			PIOq <= DDi;

	// generate PIOgo signal
	always@(posedge clk)
	begin
		dPIOreq <= PIOreq & !PIOack;
		PIOgo <= (PIOreq & !dPIOreq) & IDEctrl_IDEen;
	end

	// set Timing signals
	assign T1      = PIO_cmdport_T1;
	assign T2      = PIO_cmdport_T2;
	assign T4      = PIO_cmdport_T4;
	assign Teoc    = PIO_cmdport_Teoc;
	assign IORDYen = PIO_cmdport_IORDYen;

	// hookup timing controller
	atahost_pio_tctrl #(TWIDTH, PIO_mode0_T1, PIO_mode0_T2, PIO_mode0_T4, PIO_mode0_Teoc)
		PIO_timing_controller (.clk(clk), .nReset(nReset), .rst(rst), .IORDY_en(IORDYen), .T1(T1), .T2(T2), .T4(T4), .Teoc(Teoc),
			.go(PIOgo), .we(PIOwe), .oe(PIOoe), .done(PIOdone), .dstrb(dstrb), .DIOR(PIOdior), .DIOW(PIOdiow), .IORDY(sIORDY) );

	always@(posedge clk)
		PIOack <= PIOdone | (PIOreq & !IDEctrl_IDEen); // acknowledge when done or when IDE not enabled (discard request)

endmodule
