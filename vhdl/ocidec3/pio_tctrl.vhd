--
-- file: pio_tctrl.vhd
--	description: PIO mode timing controller for ATA controller
-- author : Richard Herveille
-- rev.: 1.0 march 7th, 2001
--

--
---------------------------
-- PIO Timing controller --
---------------------------
--

--
-- Timing	PIO mode transfers
----------------------------------------------
-- T0:	cycle time
-- T1:	address valid to DIOR-/DIOW-
-- T2:	DIOR-/DIOW- pulse width
-- T2i:	DIOR-/DIOW- recovery time
-- T3:	DIOW- data setup
-- T4:	DIOW- data hold
-- T5:	DIOR- data setup
-- T6:	DIOR- data hold
-- T9:	address hold from DIOR-/DIOW- negated
-- Trd:	Read data valid to IORDY asserted
-- Ta:	IORDY setup time
-- Tb:	IORDY pulse width
--
-- Transfer sequence
----------------------------------
-- 1)	set address (DA, CS0-, CS1-)
-- 2)	wait for T1
-- 3)	assert DIOR-/DIOW-
--	   when write action present Data (timing spec. T3 always honored), enable output enable-signal
-- 4)	wait for T2
-- 5)	check IORDY
--	   when not IORDY goto 5
-- 	  when IORDY negate DIOW-/DIOR-, latch data (if read action)
--    when write, hold data for T4, disable output-enable signal
-- 6)	wait end_of_cycle_time. This is T2i or T9 or (T0-T1-T2) whichever takes the longest
-- 7)	start new cycle

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

library count;
use count.count.all;

entity PIO_tctrl is
	generic(
		TWIDTH : natural := 8;                   -- counter width

		-- PIO mode 0 settings (@100MHz clock)
		PIO_mode0_T1 : natural := 6;             -- 70ns
		PIO_mode0_T2 : natural := 28;            -- 290ns
		PIO_mode0_T4 : natural := 2;             -- 30ns
		PIO_mode0_Teoc : natural := 23           -- 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240
	);
	port(
		clk : in std_logic;                      -- master clock
		nReset : in std_logic;                   -- asynchronous active low reset
		rst : in std_logic;                      -- synchronous active high reset

		-- timing/control register settings
		IORDY_en : in std_logic;                 -- use IORDY (or not)
		T1 : in unsigned(TWIDTH -1 downto 0);    -- T1 time (in clk-ticks)
		T2 : in unsigned(TWIDTH -1 downto 0);    -- T2 time (in clk-ticks)
		T4 : in unsigned(TWIDTH -1 downto 0);    -- T4 time (in clk-ticks)
		Teoc : in unsigned(TWIDTH -1 downto 0);  -- end of cycle time

		-- control signals
		go : in std_logic;                       -- PIO controller selected (strobe signal)
		we : in std_logic;                       -- write enable signal. '0'=read from device, '1'=write to device

		-- return signals
		oe :  buffer std_logic;                  -- output enable signal
		done : out std_logic;                    -- finished cycle
		dstrb : out std_logic;                   -- data strobe, latch data (during read)

		-- ATA signals
		DIOR,                                    -- IOread signal, active high
		DIOW : buffer std_logic;                 -- IOwrite signal, active high
		IORDY : in std_logic                     -- IORDY signal
	);
end entity PIO_tctrl;

architecture structural of PIO_tctrl is
	component ro_cnt is
	generic(SIZE : natural := 8);
	port(
		clk : in std_logic;                                   -- master clock
		nReset : in std_logic := '1';                         -- asynchronous active low reset
		rst : in std_logic := '0';                            -- synchronous active high reset

		cnt_en : in std_logic := '1';                         -- count enable
		go : in std_logic;                                    -- load counter and start sequence
		done : out std_logic;                                 -- done counting
		D : in unsigned(SIZE -1 downto 0);                    -- load counter value
		Q : out unsigned(SIZE -1 downto 0);                   -- current counter value
		
		ID : in unsigned(SIZE -1 downto 0) := (others => '0') -- initial data after reset
	);
	end component ro_cnt;

	-- PIO mode 0 settings (@100MHz clock)
	constant T1_m0 : unsigned(TWIDTH -1 downto 0) := conv_unsigned(PIO_mode0_T1, TWIDTH);    -- 70ns
	constant T2_m0 : unsigned(TWIDTH -1 downto 0) := conv_unsigned(PIO_mode0_T2, TWIDTH);   -- 290ns
	constant T4_m0 : unsigned(TWIDTH -1 downto 0) := conv_unsigned(PIO_mode0_T4, TWIDTH);    -- 30ns
	constant Teoc_m0 : unsigned(TWIDTH -1 downto 0) := conv_unsigned(PIO_mode0_Teoc, TWIDTH); -- 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240

	signal T1done, T2done, T4done, Teoc_done, IORDY_done : std_logic;
	signal busy, hold_go, igo, hT2done : std_logic;
begin
	-- generate internal go strobe
	-- strecht go until ready for new cycle
	process(clk, nReset)
	begin
		if (nReset = '0') then
			busy <= '0';
			hold_go <= '0';
		elsif (clk'event and clk = '1') then
			if (rst = '1') then
				busy <= '0';
				hold_go <= '0';
			else
				busy <= (igo or busy) and not Teoc_done;
				hold_go <= go or (hold_go and busy);
			end if;
		end if;
	end process;
	igo <= hold_go and not busy;

	-- 1)	hookup T1 counter
	t1_cnt : ro_cnt generic map (SIZE => TWIDTH)
		port map (clk => clk, nReset => nReset, rst => rst, go => igo, D => T1, ID => T1_m0, done => T1done);

	-- 2)	set (and reset) DIOR-/DIOW-, set output-enable when writing to device
	T2proc: process(clk, nReset)
	begin
		if (nReset = '0') then
			DIOR <= '0';
			DIOW <= '0';
			oe   <= '0';
		elsif (clk'event and clk = '1') then
			if (rst = '1') then
				DIOR <= '0';
				DIOW <= '0';
				oe   <= '0';
			else
				DIOR <= (not we and T1done) or (DIOR and not IORDY_done);
				DIOW <= (    we and T1done) or (DIOW and not IORDY_done);
				oe   <= ( (we and igo) or oe) and not T4done; -- negate oe when t4-done
			end if;
		end if;
	end process T2proc;

	-- 3)	hookup T2 counter
	t2_cnt : ro_cnt generic map (SIZE => TWIDTH)
		port map (clk => clk, nReset => nReset, rst => rst, go => T1done, D => T2, ID => T2_m0, done => T2done);

	-- 4)	check IORDY (if used), generate release_DIOR-/DIOW- signal (ie negate DIOR-/DIOW-)
	-- hold T2done
	gen_hT2done: process(clk, nReset)
	begin
		if (nReset = '0') then
			hT2done <= '0';
		elsif (clk'event and clk = '1') then
			if (rst = '1') then
				hT2done <= '0';
			else
				hT2done <= (T2done or hT2done) and not IORDY_done;
			end if;
		end if;
	end process gen_hT2done;
	IORDY_done <= (T2done or hT2done) and (IORDY or not IORDY_en);

	-- generate datastrobe, capture data at rising DIOR- edge
	gen_dstrb: process(clk)
	begin
		if (clk'event and clk = '1') then
			dstrb <= IORDY_done;
		end if;
	end process gen_dstrb;

	-- hookup data hold counter
	dhold_cnt : ro_cnt generic map (SIZE => TWIDTH)
		port map (clk => clk, nReset => nReset, rst => rst, go => IORDY_done, D => T4, ID => T4_m0, done => T4done);
	done <= T4done; -- placing done here provides the fastest return possible, 
                  -- while still guaranteeing data and address hold-times

	-- 5)	hookup end_of_cycle counter
	eoc_cnt : ro_cnt generic map (SIZE => TWIDTH)
		port map (clk => clk, nReset => nReset, rst => rst, go => IORDY_done, D => Teoc, ID => Teoc_m0, done => Teoc_done);

end architecture structural;










