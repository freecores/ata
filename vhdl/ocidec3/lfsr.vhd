--
-- file: lfsr.vhd
--	description: Linear Feedback Shift Registers
-- author : Richard Herveille
-- rev.: 1.0 march 21th, 2001
--
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

entity lfsr is
	generic(
		TAPS : positive range 16 downto 3 :=8;
		OFFSET : natural := 0
	);
	port(
		clk : in std_logic;                 -- clock input
		ena : in std_logic;                 -- count enable
		nReset : in std_logic;              -- asynchronous active low reset
		rst : in std_logic;                 -- synchronous active high reset
		
		Q : out unsigned(TAPS downto 1);    -- count value
		Qprev : out unsigned(TAPS downto 1) -- previous count value
	);
end entity lfsr;

architecture dataflow of lfsr is
	function lsb(tap : positive range 16 downto 3; Q : unsigned(TAPS downto 1) ) return std_logic is
	begin
		case tap is
			when 3 =>
				return Q(3) xnor Q(2);
			when 4 =>
				return Q(4) xnor Q(3);
			when 5 =>
				return Q(5) xnor Q(3);
			when 6 =>
				return Q(6) xnor Q(5);
			when 7 =>
				return Q(7) xnor Q(6);
			when 8 =>
				return (Q(8) xnor Q(6)) xnor (Q(5) xnor Q(4));
			when 9 =>
				return Q(9) xnor Q(5);
			when 10 =>
				return Q(10) xnor Q(7);
			when 11 =>
				return Q(11) xnor Q(9);
			when 12 =>
				return (Q(12) xnor Q(6)) xnor (Q(4) xnor Q(1));
			when 13 =>
				return (Q(13) xnor Q(4)) xnor (Q(3) xnor Q(1));
			when 14 =>
				return (Q(14) xnor Q(5)) xnor (Q(3) xnor Q(1));
			when 15 =>
				return Q(15) xnor Q(14);
			when 16 =>
				return (Q(16) xnor Q(15)) xnor (Q(13) xnor Q(4));
		end case;
	end function lsb;

	signal msb : std_logic;
	signal iQ : unsigned(TAPS downto 1);

begin
	--
	--	generate register
	--
	gen_regs: process(clk, nReset)
		variable tmpQ : unsigned(TAPS downto 1);
		variable tmpmsb : std_logic;
	begin
		tmpQ := (others => '0');
		tmpmsb := '1';

		for n in 1 to offset loop
			tmpQ := (tmpQ(TAPS -1 downto 1) & lsb(TAPS, tmpQ) );
			tmpmsb := tmpQ(TAPS);
		end loop;

		if (nReset = '0') then
			iQ <= tmpQ;
			msb <= tmpmsb;
		elsif (clk'event and clk = '1') then
			if (rst = '1') then
				iQ <= tmpQ;
				msb <= tmpmsb;
			elsif (ena = '1') then
				iQ <= (iQ(TAPS -1 downto 1) & lsb(TAPS, iq) );
				msb <= iQ(TAPS);
			end if;
		end if;
	end process gen_regs;

	-- assign outputs
	Q <= iQ;
	Qprev <= (msb & iQ(TAPS downto 2));
end architecture dataflow;
