

library ieee;
use ieee.std_logic_1164.all;

entity reg_buf is
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
end entity reg_buf;

architecture structural of reg_buf is
begin
	process(clk, nReset)
	begin
		if (nReset = '0') then
			Q <= (others => '0');
			valid <= '0';
		elsif (clk'event and clk = '1') then
			if (rst = '1') then
				Q <= (others => '0');
				valid <= '0';
			else
				if (wr = '1') then
					Q <= D;
				end if;
				valid <= wr or (valid and not rd);
			end if;
		end if;
	end process;
end architecture structural;

