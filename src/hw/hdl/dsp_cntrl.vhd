-------------------------------------------------------------------------------
-- Title         : DSP Control
-------------------------------------------------------------------------------
-- File          : dsp_cntrl.vhd
-- Author        : Joseph Mead  mead@bnl.gov
-- Created       : 09/24/2010
-------------------------------------------------------------------------------
-- Description:
-- Provides logic to generate a tbt_gate for the tbt processing.  Uses the inputs 
-- tbt_gate_dly and tbt_gate_width to generate a tbt_trig.  Can use either an external 
-- tbt_clk or internally generate a tbt clock.
--
-- machine sel :
--  0 = ALS
--  3 = Booster 
--  others = SR, Linac, LTB, BTS

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Modification history:
-- 09/24/2010: created.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library work;
use work.bpm_package.ALL;

entity dsp_cntrl is
  
  port (
    adc_clk         : in std_logic;              
    tbt_extclk      : in std_logic;  
    reset	        : in std_logic; 
    tbt_params      : in t_reg_o_tbt;
    inttrig_enb     : in  std_logic;
    evrsync_cnt     : in  std_logic;
    evr_sa_trig     : in  std_logic;
    evr_fa_trig     : in  std_logic;
    tbt_trig        : out std_logic;
    tbt_gate        : out std_logic;
    pt_trig         : out std_logic;
    fa_trig         : out std_logic;
    sa_trig         : out std_logic;
    sa_count        : out std_logic_vector(31 downto 0)
  );    
 
end dsp_cntrl;

architecture rtl of dsp_cntrl is
  

  type  state_type is (IDLE, TBT_DLY);  
  signal state :  state_type;
 
  type  b_state_type is (IDLE, B_ACTIVE);  
  signal b_state :  b_state_type; 
  
  signal tbt_sync_clk     : std_logic;
  signal tbt_sync_clk_1   : std_logic;
  signal tbt_gate_dly_cnt : std_logic_vector(31 downto 0);
  signal tbt_gate_width_cnt : std_logic_vector(15 downto 0);
  
  signal tbt_trig_ext      : std_logic;
  signal tbt_trig_int      : std_logic;
  signal tbt_trig_sel      : std_logic;
  signal tbt_trig_r        : std_logic;
  signal tbt_trig_dly_i    : std_logic;
  signal tbt_gate_i        : std_logic;
  signal booster_trig      : std_logic;

  signal tbt_prev		   : std_logic;

  signal booster_revcnt   : std_logic_vector(3 downto 0);
  signal booster_adccnt   : std_logic_vector(7 downto 0);
  signal booster_trignn   : std_logic;

  signal fa_trig_i        : std_logic;
  signal sa_trig_i        : std_logic;
  signal pt_cnt           : std_logic_vector(7 downto 0);
  signal fa_cnt           : std_logic_vector(7 downto 0);
  signal sa_cnt           : std_logic_vector(19 downto 0);
  signal tbt_cnt_int      : std_logic_vector(8 downto 0);
  
  signal sa_count_i       : std_logic_vector(31 downto 0);
  
  signal evr_sa_trig_s1   : std_logic;
  signal evr_sa_trig_s2   : std_logic;
  signal evr_sa_trig_s3   : std_logic;
  signal evr_sa_trig_sync : std_logic;
  signal sa_trig_o        : std_logic;


  signal evr_fa_trig_s1   : std_logic;
  signal evr_fa_trig_s2   : std_logic;
  signal evr_fa_trig_s3   : std_logic;
  signal evr_fa_trig_sync : std_logic;
  signal fa_trig_o        : std_logic;


--  attribute mark_debug                 : string;  
--  attribute mark_debug of tbt_extclk: signal is "true";
--  attribute mark_debug of tbt_sync_clk: signal is "true";
--  attribute mark_debug of tbt_trig_ext: signal is "true";
  
--  attribute mark_debug of tbt_trig_int: signal is "true";
--  attribute mark_debug of tbt_cnt_int : signal is "true";
--  attribute mark_debug of tbt_trig_sel : signal is "true";
--  attribute mark_debug of tbt_trig_r : signal is "true";   
--  attribute mark_debug of tbt_trig_dly_i : signal is "true";
--  attribute mark_debug of tbt_trig: signal is "true";
  
--  attribute mark_debug of sa_count : signal is "true";
--  attribute mark_debug of evr_fa_trig_s1 : signal is "true";
--  attribute mark_debug of evr_fa_trig_s2 : signal is "true";
--  attribute mark_debug of evr_fa_trig_s3 : signal is "true";
--  attribute mark_debug of evr_fa_trig_sync : signal is "true";
--  attribute mark_debug of fa_trig_o: signal is "true";
--  attribute mark_debug of sa_trig_o: signal is "true";           


begin  

fa_trig <= fa_trig_o;
sa_trig <= sa_trig_o;
sa_count <= sa_count_i;


--select between evr or internal trigger.
fa_trig_o  <= fa_trig_i when (inttrig_enb = '0') else evr_fa_trig_sync;
sa_trig_o  <= sa_trig_i when (inttrig_enb = '0') else evr_sa_trig_sync;





--synchronize evr_sa_trig;
process (adc_clk,reset)
  begin
    if (reset = '1') then
       evr_sa_trig_s1 <= '0';
       evr_sa_trig_s2 <= '0';
       evr_sa_trig_s3 <= '0';
       evr_sa_trig_sync <= '0';
    elsif (adc_clk'event and adc_clk = '1') then
        evr_sa_trig_s1 <= evr_sa_trig;
        evr_sa_trig_s2 <= evr_sa_trig_s1;
        evr_sa_trig_s3 <= evr_sa_trig_s2;    
        if (evr_sa_trig_s3 = '0') and (evr_sa_trig_s2 = '1') then
           evr_sa_trig_sync <= '1';
        else
           evr_sa_trig_sync <= '0';
        end if;
    end if;
end process;

--synchronize evr_fa_trig;
process (adc_clk,reset)
  begin
    if (reset = '1') then
       evr_fa_trig_s1 <= '0';
       evr_fa_trig_s2 <= '0';
       evr_fa_trig_s3 <= '0';
       evr_fa_trig_sync <= '0';
    elsif (adc_clk'event and adc_clk = '1') then
        evr_fa_trig_s1 <= evr_fa_trig;
        evr_fa_trig_s2 <= evr_fa_trig_s1;
        evr_fa_trig_s3 <= evr_fa_trig_s2;    
        if (evr_fa_trig_s3 = '0') and (evr_fa_trig_s2 = '1') then
           evr_fa_trig_sync <= '1';
        else
           evr_fa_trig_sync <= '0';
        end if;
    end if;
end process;


--sa counter
process (adc_clk,reset)
  begin
    if (reset = '1') then
       sa_count_i <= (others => '0');
    elsif (adc_clk'event and adc_clk = '1') then
        if (sa_trig_o = '1') then
           sa_count_i <= sa_count_i + 1;
        end if;
    end if;
end process;



--register outputs
process (adc_clk)
  begin
    if (adc_clk'event and adc_clk = '1') then
        tbt_trig <= tbt_trig_dly_i;
        tbt_gate <= tbt_gate_i;
    end if;
end process;


--sync tbt_clk with adc_clk
--should already be sync'd unless PLL is not locked
process (adc_clk, reset)
   begin
      if (reset = '1')  then
	     tbt_sync_clk_1 <= '0';
	     tbt_sync_clk   <= '0';
      elsif (adc_clk'event and adc_clk = '1') then
			tbt_sync_clk_1 <= tbt_extclk;
	        tbt_sync_clk   <= tbt_sync_clk_1;
      end if;
   end process;


-- generate tbt_trig (single adc_clk long trig signal)
process (adc_clk, reset)
   begin
      if (reset = '1')  then
	     tbt_prev  <= '0';
	     tbt_trig_ext   <= '0';
      elsif (adc_clk'event and adc_clk = '1') then
			   tbt_prev <= tbt_sync_clk;
				if (tbt_sync_clk = '1') and (tbt_prev = '0') then
						tbt_trig_ext <= '1';
			    else
						tbt_trig_ext <= '0';
				end if;
      end if;
   end process;




--generate internal tbt_trig
--if tbt_intenb = 1, will use this for tbt
process (adc_clk, reset)
   begin
      if (reset = '1')  then
	     tbt_trig_int  <= '0';
	     tbt_cnt_int   <= (others => '0');
      elsif (adc_clk'event and adc_clk = '1') then
                if ((tbt_cnt_int = x"3D")  AND (tbt_params.mach_sel = "01")) OR     --NSLSII Booster
				   (tbt_cnt_int = x"135")  then   --NSLSII SR
						tbt_trig_int <= '1';
						tbt_cnt_int  <= (others => '0');
			    else
			            tbt_trig_int <= '0';
						tbt_cnt_int <= tbt_cnt_int + 1;
				end if;
				
      end if;
 end process;



-- generate tbt_trig for booster
-- must generate 5 pulses for every 1 external tbt pulse
process (adc_clk, reset)
   begin
      if (reset = '1') then
	     booster_trig   <= '0';
	     booster_revcnt <= x"0";
	     booster_adccnt <= x"00";
	     b_state <= idle;
      elsif (adc_clk'event and adc_clk = '1') then
          case b_state is
            when IDLE => 
                booster_revcnt <= x"0";
                booster_adccnt <= x"00";            
				if (tbt_trig_ext = '1')  then
				      booster_trig   <= '1';  
					  b_state <= b_active;
				end if;
			when B_ACTIVE =>
			    booster_trig   <= '0';
			    booster_adccnt <= booster_adccnt + 1;
			    if (booster_revcnt = x"4") then
			        b_state <= idle;
			    end if;
			    if (booster_adccnt = x"3D") then
			        booster_trig   <= '1';
			        booster_adccnt <= x"00";
			        booster_revcnt <= booster_revcnt + 1;
			    end if;
			when others =>
			    b_state <= IDLE;
          end case;			 
      end if;
   end process;



-- tbt select
-- select which tbt signal we are really using depending on whether
-- internal mode or booster or external.
-- Choices are external tbt_trig, booster_tbt or internal tbt

tbt_trig_sel <= tbt_trig_int when (inttrig_enb = '0') else
              booster_trig when (tbt_params.mach_sel = "01")  else
              tbt_trig_ext;

tbt_sel : process (adc_clk, reset)
    begin
        if (reset = '1') then
             tbt_trig_r <= '0';
        elsif (adc_clk'event and adc_clk = '1') then    
             tbt_trig_r <= tbt_trig_sel;
        end if;
    end process;


 
--generate programmable tbt delay and gate
tbt_gate_gen : process (adc_clk, reset)
begin  
  if (reset = '1') then         
    tbt_gate_i <= '0';
    tbt_gate_width_cnt <= (others => '0');
    tbt_gate_dly_cnt  <= (others => '0');
    tbt_trig_dly_i <= '0';
    state <= IDLE;

  elsif (adc_clk'event and adc_clk = '1') then
    case state is
      when IDLE =>     
	      tbt_trig_dly_i <= '0';
		  tbt_gate_i <= '0';
          if (tbt_trig_r = '1') then
              tbt_gate_dly_cnt   <= 23d"0" & tbt_params.gate_delay;
              tbt_gate_width_cnt <= 7d"0" & tbt_params.gate_width; --x"0010"; --tbt_gate_width;
              state <= tbt_dly;
          end if;

      when TBT_DLY =>                   
          tbt_gate_dly_cnt <= tbt_gate_dly_cnt - 1;
          if (tbt_gate_dly_cnt = x"00000000") then
              tbt_trig_dly_i <= '1';
              tbt_gate_i <= '1';
              state <= idle;
          else
              tbt_gate_dly_cnt <= tbt_gate_dly_cnt - 1;
          end if;
 
      when others =>
          state <= IDLE;
    end case;
  end if;
end process tbt_gate_gen;




--generate pt_trig
process (adc_clk, reset)
   begin
      if (reset = '1')  then
         pt_trig   <= '0';
	     pt_cnt   <= (others => '0');
      elsif (adc_clk'event and adc_clk = '1') then
				pt_trig <= '0';
				if (tbt_trig_r = '1') then
				    if (pt_cnt = x"01") then
						pt_trig <= '1';
						pt_cnt <= (others => '0');
			        else
						pt_cnt <= pt_cnt + 1;
					end if;
				end if;
      end if;
   end process;




--generate fa_trig
process (adc_clk, reset)
   begin
      if (reset = '1')  then
	     fa_trig_i  <= '0';
	     fa_cnt     <= (others => '0');
      elsif (adc_clk'event and adc_clk = '1') then
				fa_trig_i <= '0';
				if (evrsync_cnt = '1') then
				    fa_cnt <= (others => '0');
				end if;
				if (tbt_trig_r = '1') then
                    if ((fa_cnt = 8d"190") AND (tbt_params.mach_sel = "01")) OR   --Booster
				       (fa_cnt = 8d"37") then  --SR
						fa_trig_i <= '1';
						fa_cnt <= (others => '0');
			        else
						fa_cnt <= fa_cnt + 1;
					end if;
				end if;
      end if;
   end process;


--generate sa_trig
process (adc_clk, reset)
   begin
      if (reset = '1')  then
	     sa_trig_i  <= '0';
	     sa_cnt     <= (others => '0');
      elsif (adc_clk'event and adc_clk = '1') then
				sa_trig_i <= '0';
				if (evrsync_cnt = '1') then
				    sa_cnt <= (others => '0');
				end if;
				if (tbt_trig_r = '1') then
                    if ((sa_cnt = 20d"190000") AND (tbt_params.mach_sel = "01")) OR   --Booster
				       (sa_cnt = 20d"38000")   then  --SR
						sa_trig_i <= '1';
						sa_cnt   <= (others => '0');
			        else
						sa_cnt <= sa_cnt + 1;
					end if;
				end if;
      end if;
   end process;









  
end rtl;
