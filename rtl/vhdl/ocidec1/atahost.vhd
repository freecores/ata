--
-- Project:		AT Atachement interface
-- ATA-3 rev7B compliant
-- Author:		Richard Herveille
-- Version:		1.0 Alpha version	march 22nd, 2001
--
-- rev.: 1.0a april 12th, 2001. Removed references to records.vhd to make it compatible with freely available VHDL to Verilog converter tools
-- rev.: 1.1  june  18th, 2001. Changed wishbone address-input from (A4..A0) to (A6..A2)
-- rev.: 1.1a june  19th, 2001. Missed a reference to ADR_I(4). Simplified DAT_O output multiplexor.
--

-- DeviceType: OCIDEC-1: OpenCores IDE Controller type1
-- Features: PIO Compatible Timing
-- DeviceID: 0x01
-- RevNo : 0x00

--
-- Host signals:
-- Reset
-- DIOR-		read strobe. The falling edge enables data from device onto DD. The rising edge latches data at the host.
-- DIOW-		write strobe. The rising edge latches data from DD into the device.
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
		PIO_mode0_Teoc : natural := 23              -- 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240
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

		-- ATA signals
		RESETn	: out std_logic;
		DDi	: in std_logic_vector(15 downto 0);
		DDo : out std_logic_vector(15 downto 0);
		DDoe : out std_logic;
		DA	: out unsigned(2 downto 0);
		CS0n	: out std_logic;
		CS1n	: out std_logic;

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
	constant DeviceId : unsigned(3 downto 0) := x"1";
	constant RevisionNo : unsigned(3 downto 0) := x"0";

	--
	-- component declarations
	--
	component controller is
	generic(
		TWIDTH : natural := 8;                        -- counter width

		-- PIO mode 0 settings (@100MHz clock)
		PIO_mode0_T1 : natural := 6;                  -- 70ns
		PIO_mode0_T2 : natural := 28;                 -- 290ns
		PIO_mode0_T4 : natural := 2;                  -- 30ns
		PIO_mode0_Teoc : natural := 23                -- 240ns ==> T0 - T1 - T2 = 600 - 70 - 290 = 240
	);
	port(
		clk : in std_logic;  		                    	  -- master clock in
		nReset	: in std_logic := '1';                 -- asynchronous active low reset
		rst : in std_logic := '0';                    -- synchronous active high reset
		
		irq : out std_logic;                          -- interrupt request signal

		-- control / registers
		IDEctrl_rst,
		IDEctrl_IDEen : in std_logic;

		-- PIO registers
		PIO_cmdport_T1,
		PIO_cmdport_T2,
		PIO_cmdport_T4,
		PIO_cmdport_Teoc : in unsigned(7 downto 0);   -- PIO command timing
		PIO_cmdport_IORDYen : in std_logic;

		PIOreq : in std_logic;                        -- PIO transfer request
		PIOack : buffer std_logic;                    -- PIO transfer ended
		PIOa   : in unsigned(3 downto 0);             -- PIO address
		PIOd   : in std_logic_vector(15 downto 0);    -- PIO data in
		PIOq   : out std_logic_vector(15 downto 0);   -- PIO data out
		PIOwe  : in std_logic;                        -- PIO direction bit '1'=write, '0'=read

		-- ATA signals
		RESETn	: out std_logic;
		DDi	 : in std_logic_vector(15 downto 0);
		DDo  : out std_logic_vector(15 downto 0);
		DDoe : out std_logic;
		DA	  : out unsigned(2 downto 0);
		CS0n	: out std_logic;
		CS1n	: out std_logic;

		DIORn	: out std_logic;
		DIOWn	: out std_logic;
		IORDY	: in std_logic;
		INTRQ	: in std_logic
	);
	end component controller;

	-- primary address decoder
	signal CONsel, PIOsel  : std_logic;  -- controller select, IDE devices select
	signal berr : std_logic;             -- bus error
	
	-- registers
	signal IDEctrl_IDEen, IDEctrl_rst: std_logic;
	signal PIO_cmdport_T1, PIO_cmdport_T2, PIO_cmdport_T4, PIO_cmdport_Teoc : unsigned(7 downto 0);
	signal PIO_cmdport_IORDYen : std_logic;
	signal CtrlReg : std_logic_vector(31 downto 0);   -- control register

	signal PIOack : std_logic;
	signal PIOq : std_logic_vector(15 downto 0);

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

	   -- PIO accesses at least 16bit wide
		PIOsel <= CYC_I and STB_I and (ADR_I(6) and w_acc);

		-- CON accesses only 32bit wide
		CONsel <= CYC_I and STB_I and (not ADR_I(6) and dw_acc);
	end block gen_bc_dec;

	--
	-- generate registers
	--
	register_block : block
		signal sel_PIO_cmdport : std_logic; -- PIO timing registers
		signal sel_ctrl, sel_stat : std_logic;                                    -- control / status register
	begin
		-- generate register select signals
		sel_ctrl        <= CONsel and WE_I and not ADR_I(5) and not ADR_I(4) and not ADR_I(3) and not ADR_I(2); -- 0x00
		sel_stat        <= CONsel and WE_I and not ADR_I(5) and not ADR_I(4) and not ADR_I(3) and     ADR_I(2); -- 0x01
		sel_PIO_cmdport <= CONsel and WE_I and not ADR_I(5) and not ADR_I(4) and     ADR_I(3) and not ADR_I(2); -- 0x02
		-- reserved 0x03-0x0f --

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
		IDEctrl_IDEen        <= CtrlReg(7);
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

			gen_stat: process(int)
			begin
				stat(31 downto 0) <= (others => '0');                -- clear all bits (read unused bits as '0')

				stat(31 downto 28) <= std_logic_vector(DeviceId);    -- set Device ID
				stat(27 downto 24) <= std_logic_vector(RevisionNo);  -- set revision number
--				stat(7)  <= PIOtip; 
--				PIOtip is only asserted during a PIO transfer (No shit! :-) )
--				Since it is impossible to read the status register and access the PIO registers at the same time
--				this bit is useless (besides using-up resources)
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
	end block register_block;

	--
	-- hookup controller section
	--
	u1: controller
		generic map(TWIDTH => TWIDTH, PIO_mode0_T1 => PIO_mode0_T1, PIO_mode0_T2 => PIO_mode0_T2,	PIO_mode0_T4 => PIO_mode0_T4, PIO_mode0_Teoc => PIO_mode0_Teoc)
		port map(CLK_I, nRESET, RST_I, irq, IDEctrl_rst,	IDEctrl_IDEen, PIO_cmdport_T1, PIO_cmdport_T2, PIO_cmdport_T4, PIO_cmdport_Teoc, PIO_cmdport_IORDYen, 
			PIOsel, PIOack, ADR_I(5 downto 2), DAT_I(15 downto 0), PIOq, WE_I, RESETn, DDi, DDo, DDoe, DA, CS0n, CS1n, DIORn, DIOWn, IORDY, INTRQ);

	--
	-- generate WISHBONE interconnect signals
	--
	gen_WB_sigs: block
		signal Q : std_logic_vector(31 downto 0);
	begin
		-- generate acknowledge signal
		ACK_O <= PIOack or CONsel;

		-- generate error signal
		ERR_O <= CYC_I and STB_I and berr;

		-- generate interrupt signal
		INTA_O <= stat(0);
	
		-- generate output multiplexor
		with ADR_I(5 downto 2) select
			Q <= CtrlReg when "0000", -- control register
			     stat    when "0001", -- status register
			     std_logic_vector(PIO_cmdport_Teoc & PIO_cmdport_T4 & PIO_cmdport_T2 & PIO_cmdport_T1) when "0010",
			     (others => '0') when others;

		DAT_O <= (x"0000" & PIOq) when (ADR_I(6) = '1') else Q;

	end block gen_WB_sigs;

end architecture structural;





