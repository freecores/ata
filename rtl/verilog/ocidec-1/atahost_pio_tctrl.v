//
// file: pio_tctrl.v
//	description: PIO mode timing controller for ATA controller
// author : Richard Herveille
// Rev. 1.0 June 27th, 2001. Initial Verilog release
// Rev. 1.1 July  2nd, 2001. Fixed incomplete port list and some Verilog related issues.
// Rev. 1.2 July 11th, 2001. Changed 'igo' & 'hold_go' generation.

//
///////////////////////////
// PIO Timing controller //
///////////////////////////
//

//
// Timing	PIO mode transfers
//--------------------------------------------
// T0:	cycle time
// T1:	address valid to DIOR-/DIOW-
// T2:	DIOR-/DIOW- pulse width
// T2i:	DIOR-/DIOW- recovery time
// T3:	DIOW- data setup
// T4:	DIOW- data hold
// T5:	DIOR- data setup
// T6:	DIOR- data hold
// T9:	address hold from DIOR-/DIOW- negated
// Trd:	Read data valid to IORDY asserted
// Ta:	IORDY setup time
// Tb:	IORDY pulse width
//
// Transfer sequence
//--------------------------------
// 1)	set address (DA, CS0-, CS1-)
// 2)	wait for T1
// 3)	assert DIOR-/DIOW-
//	   when write action present Data (timing spec. T3 always honored), enable output enable-signal
// 4)	wait for T2
// 5)	check IORDY
//	   when not IORDY goto 5
// 	  when IORDY negate DIOW-/DIOR-, latch data (if read action)
//    when write, hold data for T4, disable output-enable signal
// 6)	wait end_of_cycle_time. This is T2i or T9 or (T0-T1-T2) whichever takes the longest
// 7)	start new cycle

`include "timescale.v"

module atahost_pio_tctrl(clk, nReset, rst, IORDY_en, T1, T2, T4, Teoc, go, we, oe, done, dstrb, DIOR, DIOW, IORDY);
	// parameter declarations
	parameter TWIDTH = 8;
	parameter PIO_MODE0_T1   =  6;             // 70ns
	parameter PIO_MODE0_T2   = 28;             // 290ns
	parameter PIO_MODE0_T4   =  2;             // 30ns
	parameter PIO_MODE0_Teoc = 23;             // 240ns
	
	// inputs & outputs
	input clk; // master clock
	input nReset; // asynchronous active low reset
	input rst; // synchronous active high reset
	
	// timing & control register settings
	input IORDY_en;          // use IORDY (or not)
	input [TWIDTH-1:0] T1;   // T1 time (in clk-ticks)
	input [TWIDTH-1:0] T2;   // T1 time (in clk-ticks)
	input [TWIDTH-1:0] T4;   // T1 time (in clk-ticks)
	input [TWIDTH-1:0] Teoc; // T1 time (in clk-ticks)

	// control signals
	input go; // PIO controller selected (strobe signal)
	input we; // write enable signal. 1'b0 == read, 1'b1 == write

	// return signals
	output oe; // output enable signal
	reg oe;
	output done; // finished cycle
	output dstrb; // data strobe, latch data (during read)
	reg dstrb;

	// ata signals
	output DIOR; // IOread signal, active high
	reg DIOR;
	output DIOW; // IOwrite signal, active high
	reg DIOW;
	input  IORDY; // IOrDY signal


	//
	// constant declarations
	//
	// PIO mode 0 settings (@100MHz clock)
	wire [TWIDTH-1:0] T1_m0   = PIO_MODE0_T1;
	wire [TWIDTH-1:0] T2_m0   = PIO_MODE0_T2;
	wire [TWIDTH-1:0] T4_m0   = PIO_MODE0_T4;
	wire [TWIDTH-1:0] Teoc_m0 = PIO_MODE0_Teoc;

	//
	// variable declaration
	//
	reg busy, hold_go;
	wire igo;
	wire T1done, T2done, T4done, Teoc_done, IORDY_done;
	reg hT2done;

	//
	// module body
	//

	// generate internal go strobe
	// strecht go until ready for new cycle
	always@(posedge clk or negedge nReset)
		if (~nReset)
			begin
				busy <= 1'b0;
				hold_go <= 1'b0;
			end
		else if (rst)
			begin
				busy <= 1'b0;
				hold_go <= 1'b0;
			end
		else
			begin
				busy <= (igo | busy) & !Teoc_done;
				hold_go <= (go | (hold_go & busy)) & !igo;
			end

	assign igo = (go | hold_go) & !busy;

	// 1)	hookup T1 counter
	ro_cnt #(TWIDTH) t1_cnt(.clk(clk), .nReset(nReset), .rst(rst), .cnt_en(1'b1), .go(igo), .d(T1), .id(T1_m0), .done(T1done), .q());

	// 2)	set (and reset) DIOR-/DIOW-, set output-enable when writing to device
	always@(posedge clk or negedge nReset)
		if (~nReset)
			begin
				DIOR <= 1'b0;
				DIOW <= 1'b0;
				oe   <= 1'b0;
			end
		else if (rst)
			begin
				DIOR <= 1'b0;
				DIOW <= 1'b0;
				oe   <= 1'b0;
			end
		else
			begin
				DIOR <= (!we & T1done) | (DIOR & !IORDY_done);
				DIOW <= ( we & T1done) | (DIOW & !IORDY_done);
				oe   <= ( (we & igo) | oe) & !T4done;           // negate oe when t4-done
			end

	// 3)	hookup T2 counter
	ro_cnt #(TWIDTH) t2_cnt(.clk(clk), .nReset(nReset), .rst(rst), .cnt_en(1'b1), .go(T1done), .d(T2), .id(T2_m0), .done(T2done), .q());

	// 4)	check IORDY (if used), generate release_DIOR-/DIOW- signal (ie negate DIOR-/DIOW-)
	// hold T2done
	always@(posedge clk or negedge nReset)
		if (~nReset)
			hT2done <= 1'b0;
		else if (rst)
			hT2done <= 1'b0;
		else
				hT2done <= (T2done | hT2done) & !IORDY_done;

	assign IORDY_done = (T2done | hT2done) & (IORDY | !IORDY_en);

	// generate datastrobe, capture data at rising DIOR- edge
	always@(posedge clk)
		dstrb <= IORDY_done;

	// hookup data hold counter
	ro_cnt #(TWIDTH) dhold_cnt(.clk(clk), .nReset(nReset), .rst(rst), .cnt_en(1'b1), .go(IORDY_done), .d(T4), .id(T4_m0), .done(T4done), .q());
	assign done = T4done; // placing done here provides the fastest return possible, 
                        // while still guaranteeing data and address hold-times

	// 5)	hookup end_of_cycle counter
	ro_cnt #(TWIDTH) eoc_cnt(.clk(clk), .nReset(nReset), .rst(rst), .cnt_en(1'b1), .go(IORDY_done), .d(Teoc), .id(Teoc_m0), .done(Teoc_done), .q());

endmodule
