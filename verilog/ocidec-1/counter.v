//
// Counter.v, contains 1) run-once down-counter  2) general purpose up-down riple-carry counter
//
// Author: Richard Herveille
// Rev. 1.0 June 27th, 2001. Initial Verilog release
// Rev. 1.1 July  2nd, 2001. Fixed incomplete port list.
//


/////////////////////////////
// general purpose counter //
/////////////////////////////

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
			Qi <= resd;
		else if (rst)
			Qi <= resd;
		else	if (~nld)
			Qi <= d;
		else if (cnt_en)
			Qi <= val[SIZE-1:0];
	end

	// assign outputs
	assign q = Qi;
	assign rco = val[SIZE];
endmodule


///////////////////////////
// run-once down-counter //
///////////////////////////

// counts D+1 cycles before generating 'DONE'

module ro_cnt (clk, nReset, rst, cnt_en, go, done, d, q, id);
	// parameter declaration
	parameter SIZE = 8;
	// inputs & outputs
	input  clk;           // master clock
	input  nReset;        // asynchronous active low reset
	input  rst;           // synchronous active high reset
	input  cnt_en;        // count enable
	input  go;            // load counter and start sequence
	output done;          // done counting
	input  [SIZE-1:0] d;  // load counter value
	output [SIZE-1:0] q;  // current counter value
	input  [SIZE-1:0] id; // initial data after reset

	// variable declarations
	reg rci;
	wire nld, rco;

	//
	// module body
	//

	always@(posedge clk or negedge nReset)
		if (~nReset)
			rci <= 1'b0;
		else if (rst)
			rci <= 1'b0;
		else if (cnt_en)
			rci <= (go | rci) & !rco;

	assign nld = !go;

	// hookup counter
	ud_cnt #(SIZE) cnt (.clk(clk), .nReset(nReset), .rst(rst), .cnt_en(cnt_en),
		.ud(1'b0), .nld(nld), .d(d), .q(q), .resd(id), .rci(rci), .rco(rco));

	// assign outputs
	assign done = rco;
endmodule

