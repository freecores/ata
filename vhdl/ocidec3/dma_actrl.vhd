--
-- file: dma_actrl.vhd
--	description: DMA (single- and multiword) mode access controller for ATA controller
-- author : Richard Herveille
-- rev.: 1.0 march 9th, 2001
--

-- Host accesses to DMA ports are 32bit wide. Accesses are made by 2 consecutive 16bit accesses to the ATA
-- device's DataPort. The MSB HostData(31:16) is transfered first, then the LSB HostData(15:0) is transfered.

--
---------------------------
-- DMA Access Controller --
---------------------------
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

entity DMA_actrl is
	generic(
		TWIDTH : natural := 8;                     -- counter width

		-- DMA mode 0 settings (@100MHz clock)
		DMA_mode0_Tm : natural := 4;               -- 50ns
		DMA_mode0_Td : natural := 21;              -- 215ns
		DMA_mode0_Teoc : natural := 21             -- 215ns ==> T0 - Td - Tm = 480 - 50 - 215 = 215
	);
	port(
		clk : in std_logic;                           -- master clock
		nReset : in std_logic;                        -- asynchronous active low reset
		rst : in std_logic;                           -- synchronous active high reset

		IDEctrl_rst : in std_logic;                   -- IDE control register bit0, 'rst'

		sel : in std_logic;                           -- DMA buffers selected
		we : in std_logic;                            -- write enable input
		ack : out std_logic;		                        -- acknowledge output

		dev0_Tm,
		dev0_Td,
		dev0_Teoc : in unsigned(7 downto 0);          -- DMA mode timing device 0
		dev1_Tm,
		dev1_Td,
		dev1_Teoc : in unsigned(7 downto 0);          -- DMA mode timing device 1

		DMActrl_DMAen,
		DMActrl_dir,
		DMActrl_BeLeC0,
		DMActrl_BeLeC1 : in std_logic;                -- control register settings

		TxD : in std_logic_vector(31 downto 0);       -- DMA transmit data
		TxFull : buffer std_logic;                    -- DMA transmit buffer full
		RxQ : out std_logic_vector(31 downto 0);      -- DMA receive data
		RxEmpty : buffer std_logic;                   -- DMA receive buffer empty
		RxFull : out std_logic;                       -- DMA receive buffer full
		DMA_req : out std_logic;                      -- DMA request to external DMA engine
		DMA_ack : in std_logic;                       -- DMA acknowledge from external DMA engine

		DMARQ : in std_logic;                         -- ATA devices request DMA transfer

		SelDev : in std_logic;                        -- Selected device	

		Go : in std_logic;                            -- Start transfer sequence
		Done : out std_logic;                         -- Transfer sequence done

		DDi : in std_logic_vector(15 downto 0);       -- Data from ATA DD bus
		DDo : out std_logic_vector(15 downto 0);      -- Data towards ATA DD bus

		DIOR,
		DIOW : buffer std_logic 
	);
end entity DMA_actrl;
 
architecture structural of DMA_actrl is
	--
	-- component declarations
	--
	component DMA_tctrl is
	generic(
		TWIDTH : natural := 8;            -- counter width

		-- DMA mode 0 settings (@100MHz clock)
		DMA_mode0_Tm : natural := 6;     -- 70ns
		DMA_mode0_Td : natural := 28;    -- 290ns
		DMA_mode0_Teoc : natural := 23   -- 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240
	);
	port(
		clk : in std_logic;                      -- master clock
		nReset : in std_logic;                   -- asynchronous active low reset
		rst : in std_logic;                      -- synchronous active high reset

		-- timing register settings
		Tm : in unsigned(TWIDTH -1 downto 0);    -- Tm time (in clk-ticks)
		Td : in unsigned(TWIDTH -1 downto 0);    -- Td time (in clk-ticks)
		Teoc : in unsigned(TWIDTH -1 downto 0);  -- end of cycle time

		-- control signals
		go : in std_logic;                       -- DMA controller selected (strobe signal)
		we : in std_logic;                       -- DMA direction '1' = write, '0' = read

		-- return signals
		done : out std_logic;                    -- finished cycle
		dstrb : out std_logic;                   -- data strobe

		-- ATA signals
		DIOR,                                    -- IOread signal, active high
		DIOW : buffer std_logic                  -- IOwrite signal, active high
	);
	end component DMA_tctrl;

	component reg_buf is
	generic (
		WIDTH : natural := 8
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		rst : in std_logic;

		D : in std_logic_vector(WIDTH -1 downto 0);
		Q : out std_logic_vector(WIDTH -1 downto 0);
		rd : in std_logic;
		wr : in std_logic;
		valid : buffer std_logic
	);
	end component reg_buf;

	component fifo is
	generic(
		DEPTH : natural := 32;                      -- fifo depth
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
	end component fifo;

	signal Tdone, Tfw : std_logic;
	signal RxWr, TxRd : std_logic;
	signal dstrb, rd_dstrb, wr_dstrb : std_logic;
	signal TxbufQ, RxbufD : std_logic_vector(31 downto 0);

begin

	-- note: *fw = *first_word, *lw = *last_word
	

	--
	-- generate DDi/DDo controls
	--
	gen_DMA_sigs: block
		signal writeDfw, writeDlw : std_logic_vector(15 downto 0);
		signal readDfw, readDlw : std_logic_vector(15 downto 0);
		signal BeLeC : std_logic; -- BigEndian <-> LittleEndian conversion
	begin
		-- generate byte_swap signal
		BeLeC <=	(not SelDev and DMActrl_BeLeC0) or (SelDev and DMActrl_BeLeC1);

		-- generate Tfw (Transfering first word)
		gen_Tfw: process(clk, nReset)
		begin
			if (nReset = '0') then
				Tfw <= '0';
			elsif (clk'event and clk = '1') then
				if (rst = '1') then
					Tfw <= '0';
				else
					Tfw <= go or (Tfw and not Tdone);
				end if;
			end if;
		end process gen_Tfw;

		-- transmit data part
		gen_writed_pipe:process(clk)
		begin
			if (clk'event and clk = '1') then
				if (TxRd = '1') then                              -- reload registers
					if (BeLeC = '1') then                           -- Do big<->little endian conversion
						writeDfw(15 downto 8) <= TxbufQ( 7 downto  0); -- TxbufQ = data from transmit buffer
						writeDfw( 7 downto 0) <= TxbufQ(15 downto  8);
						writeDlw(15 downto 8) <= TxbufQ(23 downto 16);
						writeDlw( 7 downto 0) <= TxbufQ(31 downto 24);
					else                                              -- don't do big<->little endian conversion
						writeDfw <= TxbufQ(31 downto 16);
						writeDlw <= TxbufQ(15 downto 0);
					end if;
				elsif (wr_dstrb = '1') then                          -- next word to transfer
					writeDfw <= writeDlw;
				end if;
			end if;
		end process gen_writed_pipe;
		DDo <= writeDfw;                                       -- assign DMA data out

		-- generate transmit register read request
		gen_Tx_rreq: process(clk, nReset)
		begin
			if (nReset = '0') then
				TxRd <= '0';
			elsif (clk'event and clk = '1') then
				if (rst = '1') then
					TxRd <= '0';
				else
					TxRd <= go and DMActrl_dir;
				end if;
			end if;
		end process gen_Tx_rreq;
		
		-- receive
		gen_readd_pipe:process(clk)
		begin
			if (clk'event and clk = '1') then
				if (rd_dstrb = '1') then

					readDfw <= readDlw;                   -- shift previous read word to msb
					if (BeLeC = '1') then                 -- swap bytes
						readDlw(15 downto 8) <= DDi( 7 downto 0);
						readDlw( 7 downto 0) <= DDi(15 downto 8);
					else                                  -- don't swap bytes
						readDlw <= DDi;
					end if;
				end if;
			end if;
		end process gen_readd_pipe;
		-- RxD = data to receive buffer
		RxbufD <= (readDfw & readDlw) when (BeLeC = '0') else (readDlw & readDfw);

		-- generate receive register write request
		gen_Rx_wreq: process(clk, nReset)
		begin
			if (nReset = '0') then
				RxWr <= '0';
			elsif (clk'event and clk = '1') then
				if (rst = '1') then
					RxWr <= '0';
				else
					RxWr <= not Tfw and rd_dstrb;
				end if;
			end if;
		end process gen_Rx_wreq;
	end block gen_DMA_sigs;


	--
	-- Hookup DMA read / write buffers
	--
	gen_DMAbuf: block
		signal DMArst : std_logic;
		signal RxRd, TxWr : std_logic;
		signal iRxEmpty : std_logic;
	begin
		-- generate DMA reset signal
		DMArst <= rst or IDEctrl_rst;

		Txbuf: reg_buf
			generic map (WIDTH => 32)
			port map (clk => clk, nReset => nReset, rst => DMArst, D => TxD, Q => TxbufQ, 
				rd => TxRd, wr => TxWr, valid =>	TxFull	);

		Rxbuf: fifo
			generic map (DEPTH => 7, SIZE => 32)
			port map (clk => clk, nReset => nReset, rst => DMArst, D => RxbufD, Q => RxQ,
				rreq => RxRd, wreq => RxWr, empty =>	iRxEmpty, full => RxFull	);

		RxEmpty <= iRxEmpty; -- avoid 'cannot associate OUT port with BUFFER port' error

		--
		-- generate DMA buffer access signals
		--
		RxRd <= sel and not we and not RxEmpty;
		TxWr <= sel and     we and not TxFull;

		ack <= RxRd or TxWr; -- DMA buffer access acknowledge
	end block gen_DMAbuf;

	--
	-- generate request signal for external DMA engine
	--
	gen_DMA_req: block
		signal hgo : std_logic;
		signal iDMA_req : std_logic;
	begin
		-- generate hold-go
		gen_hgo : process(clk, nReset)
		begin
			if (nReset = '0') then
				hgo <= '0';
			elsif (clk'event and clk = '1') then
				if (rst = '1') then
					hgo <= '0';
				else
					hgo <= go or (hgo and not (wr_dstrb and not Tfw) and DMActrl_dir);
				end if;
			end if;
		end process gen_hgo;

		process(clk, nReset)
			variable request : std_logic;
		begin
			if (nReset = '0') then
				iDMA_req <= '0';
			elsif (clk'event and clk = '1') then
				if (rst = '1') then
					iDMA_req <= '0';
				else
					request := (DMActrl_dir and DMARQ and not TxFull and not hgo) or not RxEmpty;
					iDMA_req <= DMActrl_DMAen and not DMA_ack and (request or iDMA_req);
--				DMA_req <= (DMActrl_DMAen and DMActrl_dir and DMARQ and not TxFull and not hgo) or not RxEmpty;
				end if;
			end if;
		end process;
		DMA_req <= iDMA_req;
	end block gen_DMA_req;


	--
	-- DMA timing controller
	--
	DMA_timing_ctrl: block
		signal Tm, Td, Teoc, Tdmack_ext : unsigned(TWIDTH -1 downto 0);
		signal dTfw, igo : std_logic;
	begin
		--
		-- generate internal GO signal
		--
		gen_igo : process(clk, nReset)
		begin
			if (nReset = '0') then
				igo <= '0';
				dTfw <= '0';
			elsif (clk'event and clk = '1') then
				if (rst = '1') then
					igo <= '0';
					dTfw <= '0';
				else
					igo <= go or (not Tfw and dTfw);
					dTfw <= Tfw;
				end if;
			end if;
		end process gen_igo;

		--
		-- select timing settings for the addressed device
		--
		sel_dev_t: process(clk)
		begin
			if (clk'event and clk = '1') then
				if (SelDev = '1') then                      -- device1 selected
					Tm         <= dev1_Tm;
					Td         <= dev1_Td;
					Teoc       <= dev1_Teoc;
				else                                        -- device0 selected
					Tm         <= dev0_Tm;
					Td         <= dev0_Td;
				end if;
			end if;
		end process sel_dev_t;

		--
		-- hookup timing controller
		--
		DMA_timing_ctrl: DMA_tctrl 
			generic map (TWIDTH => TWIDTH, 
				DMA_mode0_Tm => DMA_mode0_Tm, DMA_mode0_Td => DMA_mode0_Td, DMA_mode0_Teoc => DMA_mode0_Teoc)
			port map (clk => clk, nReset => nReset, rst => rst, Tm => Tm, Td => Td, Teoc => Teoc, 
				go => igo, we => DMActrl_dir, done => Tdone, dstrb => dstrb, DIOR => dior, DIOW => diow);

		done <= Tdone and not Tfw;             -- done transfering last word
		rd_dstrb <= dstrb and not DMActrl_dir; -- read data strobe
		wr_dstrb <= dstrb and     DMActrl_dir; -- write data strobe
	end block DMA_timing_ctrl;
		
end architecture structural;




