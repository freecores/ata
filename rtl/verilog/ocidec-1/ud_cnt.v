//
// file: ud_cnt.v (universal up/down counter)
//
// Author: Richard Herveille
// Rev. 1.0 June 27th, 2001. Initial Verilog release
// Rev. 1.1 July  2nd, 2001. Fixed incomplete port list.
//


/////////////////////////////
// general purpose counter //
/////////////////////////////

`include "timescale.v"

module ud_cnt (clk, nReset, rst, cnt_en, ud, nld, d, q, resd, rci, rco);
	// parameter declaration
	parameter SIZE  = 8;
	// inputs & outputs
	input             clk;    // master clock
	input             nReset; // asynchronous active low reset
	input             rst;    // synchronous active high reset
	input             cnt_en; // count enable
	input             ud;     // up/not down
	input             nld;    // synchronous active low load
	input  [SIZE-1:0] d;      // load counter value
	output [SIZE-1:0] q;      // current counter value
	input  [SIZE-1:0] resd;   // initial data after/during reset
	input             rci;    // carry input
	output            rco;    // carry output

	// variable declarations
	reg  [SIZE-1:0] Qi;  // intermediate value
	wire [SIZE:0]   val; // carry+result

	//
	// Module body
	//

	assign val = ud ? ( {1'b0, Qi} + rci) : ( {1'b0, Qi} - rci);

	always@(posedge clk or negedge nReset)
	begin
		if (~nReset)
			Qi <= #1 resd;
		else if (rst)
			Qi <= #1 resd;
		else	if (~nld)
			Qi <= #1 d;
		else if (cnt_en)
			Qi <= #1 val[SIZE-1:0];
	end

	// assign outputs
	assign q = Qi;
	assign rco = val[SIZE];
endmodule
