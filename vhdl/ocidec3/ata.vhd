--
-- Project:		AT Atachement interface
-- ATA-3 rev7B compliant
-- Author:		Richard Herveille
-- Version:		1.0 Alpha version Januar 1st, 2001
-- rev.: 1.0a Removed all references to records.vhd. Make core compatible with VHDL to Verilog translator tools
--            Changed DMA_req signal generation. Make the core compatible with the latest version of the OpenCores DMA engine
-- rev.: 1.1  june 18th, 2001. Changed wishbone address-input from ADR_I(4 downto 0) to ADR(6 downto 2)
-- rev.: 1.1a june 19th, 2001. Simplified DAT_O output multiplexor
--
-- DeviceType: OCIDEC-3: OpenCores IDE Controller type3
-- Features: PIO Compatible Timing, PIO Fast Timing 0/1, Single/Multiword DMA Timing 0/1
-- DeviceID: 0x03
-- RevNo : 0x00

--
-- Host signals:
-- Reset
-- DIOR-		read strobe. The falling edge enables data from device onto DD. The rising edge latches data at the host.
-- DIOW-		write strobe. The rising edge latches data from DD into the device.
-- DMACK-	DMA acknowledge
-- DA(2:0)		3bit binary coded adress
-- CS0-		select command block registers
-- CS1-		select control block registers


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;

entity atahost is
	generic(
		TWIDTH : natural := 8;                      -- counter width

		-- PIO mode 0 settings (@100MHz clock)
		PIO_mode0_T1 : natural := 6;                -- 70ns
		PIO_mode0_T2 : natural := 28;               -- 290ns
		PIO_mode0_T4 : natural := 2;                -- 30ns
		PIO_mode0_Teoc : natural := 23;             -- 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240

		-- Multiword DMA mode 0 settings (@100MHz clock)
		DMA_mode0_Tm : natural := 4;                -- 50ns
		DMA_mode0_Td : natural := 21;               -- 215ns
		DMA_mode0_Teoc : natural := 21              -- 215ns ==> T0 - Td - Tm = 480 - 50 - 215 = 215
	);
	port(
		-- WISHBONE SYSCON signals
		CLK_I	: in std_logic;		                    	-- master clock in
		nReset	: in std_logic := '1';               -- asynchronous active low reset
		RST_I : in std_logic := '0';                -- synchronous active high reset

		-- WISHBONE SLAVE signals
		CYC_I : in std_logic;                       -- valid bus cycle input
		STB_I : in std_logic;                       -- strobe/core select input
		ACK_O : out std_logic;                      -- strobe acknowledge output
		RTY_O : out std_logic;                      -- retry output
		ERR_O : out std_logic;                      -- error output
		ADR_I : in unsigned(6 downto 2);            -- A6 = '1' ATA devices selected
		                                            --          A5 = '1' CS1- asserted, '0' CS0- asserted
		                                            --          A4..A2 ATA address lines
		                                            -- A6 = '0' ATA controller selected
		DAT_I : in std_logic_vector(31 downto 0);   -- Databus in
		DAT_O : out std_logic_vector(31 downto 0);  -- Databus out
		SEL_I : in std_logic_vector(3 downto 0);    -- Byte select signals
		WE_I : in std_logic;                        -- Write enable input
		INTA_O : out std_logic;                     -- interrupt request signal IDE0

		-- DMA engine signals
		DMA_req : out std_logic;                    -- DMA request
		DMA_Ack : in std_logic;                     -- DMA acknowledge

		-- ATA signals
		RESETn	: out std_logic;
		DDi	: in std_logic_vector(15 downto 0);
		DDo : out std_logic_vector(15 downto 0);
		DDoe : out std_logic;
		DA	: out unsigned(2 downto 0);
		CS0n	: out std_logic;
		CS1n	: out std_logic;

		DMARQ	: in std_logic;
		DMACKn	: out std_logic;
		DIORn	: out std_logic;
		DIOWn	: out std_logic;
		IORDY	: in std_logic;
		INTRQ	: in std_logic
	);
end entity atahost;

architecture structural of atahost is
	--
	-- Device ID
	--
	constant DeviceId : unsigned(3 downto 0) := x"3";
	constant RevisionNo : unsigned(3 downto 0) := x"0";

	--
	-- component declarations
	--
	component controller is
	generic(
		TWIDTH : natural := 8;                   -- counter width

		-- PIO mode 0 settings (@100MHz clock)
		PIO_mode0_T1 : natural := 6;             -- 70ns
		PIO_mode0_T2 : natural := 28;            -- 290ns
		PIO_mode0_T4 : natural := 2;             -- 30ns
		PIO_mode0_Teoc : natural := 23;          -- 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240

		-- Multiword DMA mode 0 settings (@100MHz clock)
		DMA_mode0_Tm : natural := 4;             -- 50ns
		DMA_mode0_Td : natural := 21;            -- 215ns
		DMA_mode0_Teoc : natural := 21           -- 215ns ==> T0 - Td - Tm = 480 - 50 - 215 = 215
	);
	port(
		clk : in std_logic;  		                    	  -- master clock in
		nReset	: in std_logic := '1';                 -- asynchronous active low reset
		rst : in std_logic := '0';                    -- synchronous active high reset
		
		irq : out std_logic;                          -- interrupt request signal

		-- control / registers
		IDEctrl_IDEen,
		IDEctrl_rst,
		IDEctrl_ppen,
		IDEctrl_FATR0,
		IDEctrl_FATR1 : in std_logic;                 -- control register settings

		a : in unsigned(3 downto 0);                  -- address input
		d : in std_logic_vector(31 downto 0);         -- data input
		we : in std_logic;                            -- write enable input '1'=write, '0'=read

		-- PIO registers
		PIO_cmdport_T1,
		PIO_cmdport_T2,
		PIO_cmdport_T4,
		PIO_cmdport_Teoc : in unsigned(7 downto 0);
		PIO_cmdport_IORDYen : in std_logic;           -- PIO compatible timing settings
	
		PIO_dport0_T1,
		PIO_dport0_T2,
		PIO_dport0_T4,
		PIO_dport0_Teoc : in unsigned(7 downto 0);
		PIO_dport0_IORDYen : in std_logic;            -- PIO data-port device0 timing settings

		PIO_dport1_T1,
		PIO_dport1_T2,
		PIO_dport1_T4,
		PIO_dport1_Teoc : in unsigned(7 downto 0);
		PIO_dport1_IORDYen : in std_logic;            -- PIO data-port device1 timing settings

		PIOsel : in std_logic;                        -- PIO controller select
		PIOack : out std_logic;                       -- PIO controller acknowledge
		PIOq : out std_logic_vector(15 downto 0);     -- PIO data out
		PIOtip : buffer std_logic;                    -- PIO transfer in progress
		PIOpp_full : out std_logic;                   -- PIO Write PingPong full

		-- DMA registers
		DMA_dev0_Td,
		DMA_dev0_Tm,
		DMA_dev0_Teoc : in unsigned(7 downto 0);      -- DMA timing settings for device0

		DMA_dev1_Td,
		DMA_dev1_Tm,
		DMA_dev1_Teoc : in unsigned(7 downto 0);      -- DMA timing settings for device1

		DMActrl_DMAen,
		DMActrl_dir,
		DMActrl_BeLeC0,
		DMActrl_BeLeC1 : in std_logic;                -- DMA settings

		DMAsel : in std_logic;                        -- DMA controller select
		DMAack : out std_logic;                       -- DMA controller acknowledge
		DMAq : out std_logic_vector(31 downto 0);     -- DMA data out
		DMAtip : buffer std_logic;                    -- DMA transfer in progress
		DMA_dmarq : out std_logic;                    -- Synchronized ATA DMARQ line

		DMATxFull : buffer std_logic;                 -- DMA transmit buffer full
		DMARxEmpty : buffer std_logic;                -- DMA receive buffer empty

		DMA_req : out std_logic;                      -- DMA request to external DMA engine
		DMA_ack : in std_logic;                       -- DMA acknowledge from external DMA engine

		-- ATA signals
		RESETn	: out std_logic;
		DDi	: in std_logic_vector(15 downto 0);
		DDo : out std_logic_vector(15 downto 0);
		DDoe : out std_logic;
		DA	: out unsigned(2 downto 0);
		CS0n	: out std_logic;
		CS1n	: out std_logic;

		DMARQ	: in std_logic;
		DMACKn	: out std_logic;
		DIORn	: out std_logic;
		DIOWn	: out std_logic;
		IORDY	: in std_logic;
		INTRQ	: in std_logic
	);
	end component controller;

	-- primary address decoder
	signal CONsel, PIOsel, DMAsel : std_logic;        -- controller select, IDE devices select
	signal berr, brty : std_logic;                    -- bus error, bus retry

	-- registers
	-- IDE control register
	signal IDEctrl_IDEen, IDEctrl_rst, IDEctrl_ppen, IDEctrl_FATR0, IDEctrl_FATR1 : std_logic;
	-- PIO compatible timing settings
	signal PIO_cmdport_T1, PIO_cmdport_T2, PIO_cmdport_T4, PIO_cmdport_Teoc : unsigned(7 downto 0);
	signal PIO_cmdport_IORDYen : std_logic;
	-- PIO data register device0 timing settings
	signal PIO_dport0_T1, PIO_dport0_T2, PIO_dport0_T4, PIO_dport0_Teoc : unsigned(7 downto 0);
	signal PIO_dport0_IORDYen : std_logic;  
	-- PIO data register device1 timing settings
	signal PIO_dport1_T1, PIO_dport1_T2, PIO_dport1_T4, PIO_dport1_Teoc : unsigned(7 downto 0);
	signal PIO_dport1_IORDYen : std_logic;
	-- DMA control register
	signal DMActrl_DMAen, DMActrl_dir, DMActrl_BeLeC0, DMActrl_BeLeC1 : std_logic;
	-- DMA data port device0 timing settings
	signal DMA_dev0_Td, DMA_dev0_Tm, DMA_dev0_Teoc : unsigned(7 downto 0);
	-- DMA data port device1 timing settings
	signal DMA_dev1_Td, DMA_dev1_Tm, DMA_dev1_Teoc : unsigned(7 downto 0);

	signal CtrlReg : std_logic_vector(31 downto 0);   -- control register

	signal PIOack, DMAack, PIOtip, DMAtip : std_logic;
	signal PIOq : std_logic_vector(15 downto 0);
	signal PIOpp_full : std_logic;
	signal DMAq : std_logic_vector(31 downto 0);
	signal DMA_dmarq : std_logic; -- synchronized version of DMARQ

	signal DMATxFull, DMARxEmpty : std_logic;

	signal stat : std_logic_vector(31 downto 0);

	signal irq : std_logic; -- ATA bus IRQ signal

begin
	--
	-- generate bus cycle / address decoder
	--
	gen_bc_dec: block
		signal w_acc, dw_acc : std_logic;      -- word access, double word access
		signal store_pp_full : std_logic;
	begin
		-- word / double word
		w_acc  <= SEL_I(1) and SEL_I(0);
		dw_acc <= SEL_I(3) and SEL_I(2) and SEL_I(1) and SEL_I(0);

		-- bus error
		berr  <= (ADR_I(6) and not w_acc) or (not ADR_I(6) and not dw_acc);

		-- bus retry
		-- store PIOpp_full, we don't want a PPfull based retry initiated by the current bus-cycle
		process(CLK_I)
		begin
			if (CLK_I'event and CLK_I = '1') then
				if (PIOsel = '0') then
					store_pp_full <= PIOpp_full;
				end if;
			end if;
		end process;
		brty <= (ADR_I(6) and w_acc) and (DMAtip or store_pp_full);

	   -- PIO accesses at least 16bit wide, no PIO access during     DMAtip or pingpong full
		PIOsel <= CYC_I and STB_I and (ADR_I(6) and w_acc) and not (DMAtip or store_pp_full);

		-- CON accesses only 32bit wide
		CONsel <= CYC_I and STB_I and (not ADR_I(6) and dw_acc);
		DMAsel <= CONsel and ADR_I(5) and ADR_I(4) and ADR_I(3) and ADR_I(2);
	end block gen_bc_dec;

	--
	-- generate registers
	--
	register_block : block
		signal sel_PIO_cmdport, sel_PIO_dport0, sel_PIO_dport1 : std_logic; -- PIO timing registers
		signal sel_DMA_dev0, sel_DMA_dev1 : std_logic;                      -- DMA timing registers
		signal sel_ctrl, sel_stat : std_logic;                              -- control / status register
	begin
		-- generate register select signals
		sel_ctrl        <= CONsel and WE_I and not ADR_I(5) and not ADR_I(4) and not ADR_I(3) and not ADR_I(2); -- 0x00
		sel_stat        <= CONsel and WE_I and not ADR_I(5) and not ADR_I(4) and not ADR_I(3) and     ADR_I(2); -- 0x04
		sel_PIO_cmdport <= CONsel and WE_I and not ADR_I(5) and not ADR_I(4) and     ADR_I(3) and not ADR_I(2); -- 0x08
		sel_PIO_dport0  <= CONsel and WE_I and not ADR_I(5) and not ADR_I(4) and     ADR_I(3) and     ADR_I(2); -- 0x0C
		sel_PIO_dport1  <= CONsel and WE_I and not ADR_I(5) and     ADR_I(4) and not ADR_I(3) and not ADR_I(2); -- 0x10
		sel_DMA_dev0    <= CONsel and WE_I and not ADR_I(5) and     ADR_I(4) and not ADR_I(3) and     ADR_I(2); -- 0x14
		sel_DMA_dev1    <= CONsel and WE_I and not ADR_I(5) and     ADR_I(4) and     ADR_I(3) and not ADR_I(2); -- 0x18
		-- reserved 0x1C-0x38 --
		-- reserved 0x3C : DMA port --

		-- generate control register
		gen_ctrl_reg: process(CLK_I, nRESET)
		begin
			if (nRESET = '0') then
				CtrlReg(31 downto 1) <= (others => '0');
				CtrlReg(0)           <= '1';                -- set reset bit
			elsif (CLK_I'event and CLK_I = '1') then
				if (RST_I = '1') then
					CtrlReg(31 downto 1) <= (others => '0');
					CtrlReg(0)           <= '1';                -- set reset bit
				elsif (sel_ctrl = '1') then
					CtrlReg <= DAT_I;
				end if;
			end if;
		end process gen_ctrl_reg;
		-- assign bits
		DMActrl_DMAen        <= CtrlReg(15);
		DMActrl_dir          <= CtrlReg(13);
		DMActrl_BeLeC1       <= CtrlReg(9);
		DMActrl_BeLeC0       <= CtrlReg(8);
		IDEctrl_IDEen        <= CtrlReg(7);
		IDEctrl_FATR1        <= CtrlReg(6);
		IDEctrl_FATR0        <= CtrlReg(5);
		IDEctrl_ppen         <= CtrlReg(4);
		PIO_dport1_IORDYen   <= CtrlReg(3);
		PIO_dport0_IORDYen   <= CtrlReg(2);
		PIO_cmdport_IORDYen  <= CtrlReg(1);
		IDEctrl_rst          <= CtrlReg(0);

		-- generate status register clearable bits
		gen_stat_reg: block
			signal dirq, int : std_logic;
		begin
			gen_irq: process(CLK_I, nRESET)
			begin
				if (nRESET = '0') then
					int <= '0';
					dirq <= '0';
				elsif (CLK_I'event and CLK_I = '1') then
					if (RST_I = '1') then
						int <= '0';
						dirq <= '0';
					else
						int <= (int or (irq and not dirq)) and not (sel_stat and not DAT_I(0));
						dirq <= irq;
					end if;
				end if;
			end process gen_irq;

			gen_stat: process(DMAtip, DMARxEmpty, DMATxFull, DMA_dmarq, PIOtip, int, PIOpp_full)
			begin
				stat(31 downto 0) <= (others => '0');                -- clear all bits (read unused bits as '0')

				stat(31 downto 28) <= std_logic_vector(DeviceId);    -- set Device ID
				stat(27 downto 24) <= std_logic_vector(RevisionNo);  -- set revision number
				stat(15) <= DMAtip;
				stat(10) <= DMARxEmpty;
				stat(9)  <= DMATxFull;
				stat(8)  <= DMA_dmarq;
				stat(7)  <= PIOtip;
				stat(6)  <= PIOpp_full;
				stat(0)  <= int;
			end process;
		end block gen_stat_reg;

		-- generate PIO compatible / command-port timing register
		gen_PIO_cmdport_reg: process(CLK_I, nRESET)
		begin
			if (nRESET = '0') then
				PIO_cmdport_T1   <= conv_unsigned(PIO_mode0_T1, TWIDTH);
				PIO_cmdport_T2   <= conv_unsigned(PIO_mode0_T2, TWIDTH);
				PIO_cmdport_T4   <= conv_unsigned(PIO_mode0_T4, TWIDTH);
				PIO_cmdport_Teoc <= conv_unsigned(PIO_mode0_Teoc, TWIDTH);
			elsif (CLK_I'event and CLK_I = '1') then
				if (RST_I = '1') then
					PIO_cmdport_T1   <= conv_unsigned(PIO_mode0_T1, TWIDTH);
					PIO_cmdport_T2   <= conv_unsigned(PIO_mode0_T2, TWIDTH);
					PIO_cmdport_T4   <= conv_unsigned(PIO_mode0_T4, TWIDTH);
					PIO_cmdport_Teoc <= conv_unsigned(PIO_mode0_Teoc, TWIDTH);
				elsif (sel_PIO_cmdport = '1') then
					PIO_cmdport_T1   <= unsigned(DAT_I( 7 downto  0));
					PIO_cmdport_T2   <= unsigned(DAT_I(15 downto  8));
					PIO_cmdport_T4   <= unsigned(DAT_I(23 downto 16));
					PIO_cmdport_Teoc <= unsigned(DAT_I(31 downto 24));
				end if;
			end if;
		end process gen_PIO_cmdport_reg;

		-- generate PIO device0 timing register
		gen_PIO_dport0_reg: process(CLK_I, nRESET)
		begin
			if (nRESET = '0') then
				PIO_dport0_T1   <= conv_unsigned(PIO_mode0_T1, TWIDTH);
				PIO_dport0_T2   <= conv_unsigned(PIO_mode0_T2, TWIDTH);
				PIO_dport0_T4   <= conv_unsigned(PIO_mode0_T4, TWIDTH);
				PIO_dport0_Teoc <= conv_unsigned(PIO_mode0_Teoc, TWIDTH);
			elsif (CLK_I'event and CLK_I = '1') then
				if (RST_I = '1') then
					PIO_dport0_T1   <= conv_unsigned(PIO_mode0_T1, TWIDTH);
					PIO_dport0_T2   <= conv_unsigned(PIO_mode0_T2, TWIDTH);
					PIO_dport0_T4   <= conv_unsigned(PIO_mode0_T4, TWIDTH);
					PIO_dport0_Teoc <= conv_unsigned(PIO_mode0_Teoc, TWIDTH);
				elsif (sel_PIO_dport0 = '1') then
					PIO_dport0_T1   <= unsigned(DAT_I( 7 downto  0));
					PIO_dport0_T2   <= unsigned(DAT_I(15 downto  8));
					PIO_dport0_T4   <= unsigned(DAT_I(23 downto 16));
					PIO_dport0_Teoc <= unsigned(DAT_I(31 downto 24));
				end if;
			end if;
		end process gen_PIO_dport0_reg;

		-- generate PIO device1 timing register
		gen_PIO_dport1_reg: process(CLK_I, nRESET)
		begin
			if (nRESET = '0') then
				PIO_dport1_T1   <= conv_unsigned(PIO_mode0_T1, TWIDTH);
				PIO_dport1_T2   <= conv_unsigned(PIO_mode0_T2, TWIDTH);
				PIO_dport1_T4   <= conv_unsigned(PIO_mode0_T4, TWIDTH);
				PIO_dport1_Teoc <= conv_unsigned(PIO_mode0_Teoc, TWIDTH);
			elsif (CLK_I'event and CLK_I = '1') then
				if (RST_I = '1') then
					PIO_dport1_T1   <= conv_unsigned(PIO_mode0_T1, TWIDTH);
					PIO_dport1_T2   <= conv_unsigned(PIO_mode0_T2, TWIDTH);
					PIO_dport1_T4   <= conv_unsigned(PIO_mode0_T4, TWIDTH);
					PIO_dport1_Teoc <= conv_unsigned(PIO_mode0_Teoc, TWIDTH);
				elsif (sel_PIO_dport1 = '1') then
					PIO_dport1_T1   <= unsigned(DAT_I( 7 downto  0));
					PIO_dport1_T2   <= unsigned(DAT_I(15 downto  8));
					PIO_dport1_T4   <= unsigned(DAT_I(23 downto 16));
					PIO_dport1_Teoc <= unsigned(DAT_I(31 downto 24));
				end if;
			end if;
		end process gen_PIO_dport1_reg;

		-- generate DMA device0 timing register
		gen_DMA_dev0_reg: process(CLK_I, nRESET)
		begin
			if (nRESET = '0') then
				DMA_dev0_Tm   <= conv_unsigned(DMA_mode0_Tm, TWIDTH);
				DMA_dev0_Td   <= conv_unsigned(DMA_mode0_Td, TWIDTH);
				DMA_dev0_Teoc <= conv_unsigned(DMA_mode0_Teoc, TWIDTH);
			elsif (CLK_I'event and CLK_I = '1') then
				if (RST_I = '1') then
					DMA_dev0_Tm   <= conv_unsigned(DMA_mode0_Tm, TWIDTH);
					DMA_dev0_Td   <= conv_unsigned(DMA_mode0_Td, TWIDTH);
					DMA_dev0_Teoc <= conv_unsigned(DMA_mode0_Teoc, TWIDTH);
				elsif (sel_DMA_dev0 = '1') then
					DMA_dev0_Tm   <= unsigned(DAT_I( 7 downto  0));
					DMA_dev0_Td   <= unsigned(DAT_I(15 downto  8));
					DMA_dev0_Teoc <= unsigned(DAT_I(31 downto 24));
				end if;
			end if;
		end process gen_DMA_dev0_reg;

		-- generate DMA device0 timing register
		gen_DMA_dev1_reg: process(CLK_I, nRESET)
		begin
			if (nRESET = '0') then
				DMA_dev1_Tm   <= conv_unsigned(DMA_mode0_Tm, TWIDTH);
				DMA_dev1_Td   <= conv_unsigned(DMA_mode0_Td, TWIDTH);
				DMA_dev1_Teoc <= conv_unsigned(DMA_mode0_Teoc, TWIDTH);
			elsif (CLK_I'event and CLK_I = '1') then
				if (RST_I = '1') then
					DMA_dev1_Tm   <= conv_unsigned(DMA_mode0_Tm, TWIDTH);
					DMA_dev1_Td   <= conv_unsigned(DMA_mode0_Td, TWIDTH);
					DMA_dev1_Teoc <= conv_unsigned(DMA_mode0_Teoc, TWIDTH);
				elsif (sel_DMA_dev1 = '1') then
					DMA_dev1_Tm   <= unsigned(DAT_I( 7 downto  0));
					DMA_dev1_Td   <= unsigned(DAT_I(15 downto  8));
					DMA_dev1_Teoc <= unsigned(DAT_I(31 downto 24));
				end if;
			end if;
		end process gen_DMA_dev1_reg;

	end block register_block;

	--
	-- hookup controller section
	--
	u1: controller
		generic map(TWIDTH => TWIDTH, PIO_mode0_T1 => PIO_mode0_T1, PIO_mode0_T2 => PIO_mode0_T2,	PIO_mode0_T4 => PIO_mode0_T4,
			PIO_mode0_Teoc => PIO_mode0_Teoc, DMA_mode0_Tm => DMA_mode0_Tm, DMA_mode0_Td => DMA_mode0_Td, DMA_mode0_Teoc => DMA_mode0_Teoc)
		port map(clk => CLK_I, nReset => nRESET, rst => RST_I, irq => irq, IDEctrl_IDEen => IDEctrl_IDEen, IDEctrl_rst => IDEctrl_rst, IDEctrl_ppen => IDEctrl_ppen, 
			IDEctrl_FATR0 => IDEctrl_FATR0, IDEctrl_FATR1 => IDEctrl_FATR1,	a => ADR_I(5 downto 2), d => DAT_I, we => WE_I, 
			PIO_cmdport_T1 => PIO_cmdport_T1, PIO_cmdport_T2 => PIO_cmdport_T2, PIO_cmdport_T4 => PIO_cmdport_T4, PIO_cmdport_Teoc => PIO_cmdport_Teoc, PIO_cmdport_IORDYen => PIO_cmdport_IORDYen,
			PIO_dport0_T1 => PIO_dport0_T1, PIO_dport0_T2 => PIO_dport0_T2, PIO_dport0_T4 => PIO_dport0_T4, PIO_dport0_Teoc => PIO_dport0_Teoc, PIO_dport0_IORDYen => PIO_dport0_IORDYen,
			PIO_dport1_T1 => PIO_dport1_T1, PIO_dport1_T2 => PIO_dport1_T2, PIO_dport1_T4 => PIO_dport1_T4, PIO_dport1_Teoc => PIO_dport1_Teoc, PIO_dport1_IORDYen => PIO_dport1_IORDYen,
			PIOsel => PIOsel, PIOack => PIOack, PIOq => PIOq, PIOtip => PIOtip, PIOpp_full => PIOpp_full, 
			DMActrl_DMAen => DMActrl_DMAen, DMActrl_dir => DMActrl_dir, DMActrl_BeLeC0 => DMActrl_BeLeC0, DMActrl_BeLeC1 => DMActrl_BeLeC1,
			DMA_dev0_Td => DMA_dev0_Td, DMA_dev0_Tm => DMA_dev0_Tm, DMA_dev0_Teoc => DMA_dev0_Teoc,
			DMA_dev1_Td => DMA_dev1_Td, DMA_dev1_Tm => DMA_dev1_Tm, DMA_dev1_Teoc => DMA_dev1_Teoc,
			DMAsel => DMAsel, DMAack => DMAack, DMAq => DMAq, DMAtip => DMAtip, DMA_dmarq => DMA_dmarq, DMATxFull => DMATxFull, 
			DMARxEmpty => DMARxEmpty, DMA_req => DMA_req, DMA_ack => DMA_ack, RESETn => RESETn, DDi => DDi, DDo => DDo, DDoe => DDoe, 
			DA => DA, CS0n	=> CS0n, CS1n => CS1n, DMARQ => DMARQ, DMACKn => DMACKn, DIORn => DIORn, DIOWn => DIOWn, IORDY => IORDY, INTRQ	=> INTRQ);

	--
	-- generate WISHBONE interconnect signals
	--
	gen_WB_sigs: block
		signal Q : std_logic_vector(31 downto 0);
	begin
		-- generate acknowledge signal
		ACK_O <= PIOack or CONsel; -- or DMAack; -- since DMAack is derived from CONsel this is OK

		-- generate error signal
		ERR_O <= CYC_I and STB_I and berr;

		-- generate retry signal
		RTY_O <= CYC_I and STB_I and brty;

		-- assign interrupt signal
		INTA_O <= stat(0);
	
		-- generate output multiplexor
		with ADR_I(5 downto 2) select
			Q <= CtrlReg when "0000", -- control register
			     stat    when "0001", -- status register
			     std_logic_vector(PIO_cmdport_Teoc & PIO_cmdport_T4 & PIO_cmdport_T2 & PIO_cmdport_T1) when "0010", -- PIO compatible / cmd-port timing register
			     std_logic_vector(PIO_dport0_Teoc & PIO_dport0_T4 & PIO_dport0_T2 & PIO_dport0_T1)     when "0011", -- PIO fast timing register device0
			     std_logic_vector(PIO_dport1_Teoc & PIO_dport1_T4 & PIO_dport1_T2 & PIO_dport1_T1)     when "0100", -- PIO fast timing register device1
			     std_logic_vector(DMA_dev0_Teoc & x"00" & DMA_dev0_Td & DMA_dev0_Tm)                   when "0101", -- DMA timing register device0
			     std_logic_vector(DMA_dev1_Teoc & x"00" & DMA_dev1_Td & DMA_dev1_Tm)                   when "0110", -- DMA timing register device1
			     DMAq    when "1111", -- DMA port, DMA receive register
		       (others => '0') when others;

		DAT_O <= (x"0000" & PIOq) when (ADR_I(6) = '1') else Q;
	end block gen_WB_sigs;

end architecture structural;

