--
-- file: fifo.vhd
--	description: synchronous single clock fifo, uses Linear Feedback Shift Registers as read/write pointers
-- author : Richard Herveille
-- rev.: 1.0 march 12th, 2001
--
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

entity fifo is
	generic(
		DEPTH : natural := 31;                      -- fifo depth, this must be a number according to the following range
                                                 -- 3, 7, 15, 31, 63 ... 65535
		SIZE : natural := 32                        -- data width
	);
	port(
		clk : in std_logic;                         -- master clock in
		nReset : in std_logic := '1';               -- asynchronous active low reset
		rst : in std_logic := '0';                  -- synchronous active high reset

		rreq : in std_logic;                        -- read request
		wreq : in std_logic;                        -- write request

		empty : out std_logic;                      -- fifo empty
		full : out std_logic;                       -- fifo full

		D : in std_logic_vector(SIZE -1 downto 0);  -- data input
		Q : out std_logic_vector(SIZE -1 downto 0)  -- data output
	);
end entity fifo;

architecture structural of fifo is
	--
	-- function declarations
	--
	function bitsize(n : in natural) return natural is
		variable tmp : unsigned(32 downto 1);
		variable cnt : integer;
	begin
		tmp := conv_unsigned(n, 32);
		cnt := 32;

		while ( (tmp(cnt) = '0') and (cnt > 0) ) loop
			cnt := cnt -1;
		end loop;

		return natural(cnt);
	end function bitsize;

	--
	-- component declarations
	--
	component lfsr is
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
	end component lfsr;

	constant ADEPTH : natural := bitsize(DEPTH);

	-- memory block
	type memory is array (DEPTH -1 downto 0) of std_logic_vector(SIZE -1 downto 0);
--	shared variable mem : memory; -- VHDL'93 PREFERED
	signal mem : memory; -- VHDL'87

	-- address pointers
	signal wr_ptr, rd_ptr, dwr_ptr, drd_ptr : unsigned(ADEPTH -1 downto 0);

begin
	-- generate write address; hookup write_pointer counter
	wr_ptr_lfsr: lfsr
		generic map(TAPS => ADEPTH, OFFSET => 0)
		port map(clk => clk, ena => wreq, nReset => nReset, rst => rst, Q => wr_ptr, Qprev => dwr_ptr);

	-- generate read address; hookup read_pointer counter
	rd_ptr_lfsr: lfsr 
		generic map(TAPS => ADEPTH, OFFSET => 0)
		port map(clk => clk, ena => rreq, nReset => nReset, rst => rst, Q => rd_ptr, Qprev => drd_ptr);

	-- generate full/empty signal
	full <= '1' when (wr_ptr = drd_ptr) else '0';
	empty <= '1' when (rd_ptr = wr_ptr) else '0';
	
	-- generate memory structure
	gen_mem: process(clk)
	begin
		if (clk'event and clk = '1') then
			if (wreq = '1') then
				mem(conv_integer(wr_ptr)) <= D;
			end if;
		end if;
	end process gen_mem;
	Q <= mem(conv_integer(rd_ptr));
end architecture structural;




