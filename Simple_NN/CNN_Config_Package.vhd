
library IEEE;  
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all; 
use IEEE.math_real.all;

PACKAGE CNN_Config_Package is
	CONSTANT CNN_Value_Resolution       : NATURAL := 8;
	CONSTANT CNN_Weight_Resolution      : NATURAL := 8;
	CONSTANT CNN_Parameter_Resolution   : NATURAL := 8;
	CONSTANT CNN_Input_Columns          : NATURAL := 28;
	CONSTANT CNN_Input_Rows             : NATURAL := 28;
	CONSTANT CNN_Max_Filters            : NATURAL := 8;
	CONSTANT CNN_Value_Negative         : NATURAL := 0;
	CONSTANT CNN_Mult_Sum_Group         : INTEGER := 1; -- Some DSP Blocks can multiply and add multiple values at once (e.g. 6x mult & add)
	CONSTANT CNN_Shift_Before_Sum       : BOOLEAN := False; -- Logic Elements can be reduced if the multiplication result is shifted before addition (True), but this can lower the f_max. Shifting after addition can cause a different rounding behaviour 

	subtype CNN_Value_T is INTEGER range (-1)*(2**(CNN_Value_Resolution-1)-1) to 2**(CNN_Value_Resolution-1)-1;
	type CNN_Values_T         is array (NATURAL range <>) of CNN_Value_T;
	type CNN_Value_Matrix_T   is array (NATURAL range <>, NATURAL range <>, NATURAL range <>) of CNN_Value_T;

	CONSTANT CNN_Sum_Offset             : NATURAL := 2; -- Save more bits for the sum to get higher resolution
	CONSTANT CNN_Rounding               : STD_LOGIC_VECTOR := "111"; -- 1. Bit: round each addition, 2. Bit: round sum division, 3. Bit: round whole result after bias addition
	CONSTANT CNN_Efficient_Rounding     : BOOLEAN := True;

	subtype CNN_Weight_T      is INTEGER range (-1)*(2**(CNN_Weight_Resolution-1)-1) to 2**(CNN_Weight_Resolution-1)-1;
	type CNN_Weights_T        is array (NATURAL range <>, NATURAL range <>) of CNN_Weight_T;

	subtype CNN_Parameter_T      is INTEGER range (-1)*(2**(CNN_Parameter_Resolution-1)-1) to 2**(CNN_Parameter_Resolution-1)-1;
	type CNN_Parameters_T        is array (NATURAL range <>, NATURAL range <>) of CNN_Parameter_T;

	TYPE CNN_Stream_T IS RECORD
		Column     : NATURAL range 0 to CNN_Input_Columns-1;
		Row        : NATURAL range 0 to CNN_Input_Rows-1;
		Filter     : NATURAL range 0 to CNN_Max_Filters-1;
		Data_Valid : STD_LOGIC;
		Data_CLK   : STD_LOGIC;
	END RECORD CNN_Stream_T;

	type Activation_T is (relu, linear, leaky_relu, step_func, sign_func);
	type Padding_T is (valid, same);
	type Threshold_T is (binary, tozero, toone, tozero_inv, toone_inv);
	type Upscaling_T is (nearest);

	CONSTANT leaky_relu_mult : CNN_Weight_T := (2**(CNN_Weight_Resolution-1))/10;

	FUNCTION max_val ( a : INTEGER; b : INTEGER) RETURN  INTEGER;
	FUNCTION min_val ( a : INTEGER; b : INTEGER) RETURN  INTEGER;
	FUNCTION relu_f ( i : INTEGER; max : INTEGER) RETURN  INTEGER;
	FUNCTION relu_f ( i : SIGNED; max : INTEGER) RETURN  SIGNED;
	FUNCTION linear_f ( i : INTEGER; max : INTEGER) RETURN  INTEGER;
	FUNCTION linear_f ( i : SIGNED; max : INTEGER) RETURN  SIGNED;
	FUNCTION leaky_relu_f ( i : INTEGER; max : INTEGER; max_bits : INTEGER) RETURN  INTEGER;
	FUNCTION leaky_relu_f ( i : SIGNED; max : INTEGER; max_bits : INTEGER) RETURN  SIGNED;
	FUNCTION step_f ( i : INTEGER) RETURN  INTEGER;
	FUNCTION step_f ( i : SIGNED) RETURN  SIGNED;
	FUNCTION sign_f ( i : INTEGER) RETURN  INTEGER;
	FUNCTION sign_f ( i : SIGNED) RETURN  SIGNED;
	FUNCTION Bool_Select ( Sel : BOOLEAN; Value  : NATURAL; Alternative : NATURAL) RETURN  NATURAL;
	FUNCTION shift_with_rounding(value : SIGNED; shift_amount: INTEGER) RETURN SIGNED;
	FUNCTION shift_with_rounding(value : UNSIGNED; shift_amount: INTEGER) RETURN UNSIGNED;
	FUNCTION shift_bits(value : SIGNED; shift_amount: INTEGER) RETURN SIGNED;
	FUNCTION shift_bits(value : UNSIGNED; shift_amount: INTEGER) RETURN UNSIGNED;
	FUNCTION adjust_offset(value : INTEGER; offset : INTEGER) RETURN INTEGER;
	FUNCTION unsigned_multiply_efficient(value : NATURAL; factor: REAL; resolution_val  : NATURAL := CNN_Weight_Resolution-1; resolution_fac  : natural := CNN_Weight_Resolution-1) return natural;

END PACKAGE CNN_Config_Package;

PACKAGE BODY CNN_Config_Package IS
	FUNCTION max_val ( a : INTEGER; b : INTEGER) RETURN  INTEGER IS
	BEGIN
		IF (a > b) THEN
			return a;
		ELSE
			return b;
		END IF;
	END FUNCTION;

	FUNCTION min_val ( a : INTEGER; b : INTEGER) RETURN  INTEGER IS
	BEGIN
		IF (a < b) THEN
			return a;
		ELSE
			return b;
		END IF;
	END FUNCTION;

	FUNCTION relu_f ( i : INTEGER; max : INTEGER) RETURN  INTEGER IS
	BEGIN
		IF (i > 0) THEN
			IF (i < max) THEN
				return i;
			ELSE
				return max;
			END IF;
		ELSE
			return 0;
		END IF;
	END FUNCTION;

	FUNCTION relu_f ( i : SIGNED; max : INTEGER) RETURN  SIGNED IS
	BEGIN
		IF (i > 0) THEN
			IF (i < to_signed(max, i'LENGTH)) THEN
				return i;
			ELSE
				return to_signed(max, i'LENGTH);
			END IF;
		ELSE
			return to_signed(0, i'LENGTH);
		END IF;
	END FUNCTION;

	FUNCTION linear_f ( i : INTEGER; max : INTEGER) RETURN  INTEGER IS
	BEGIN
		IF (i < max) THEN
			IF (i > max*(-1)) THEN
				return i;
			ELSE
				return max*(-1);
			END IF;
		ELSE
			return max;
		END IF;
	END FUNCTION;

	FUNCTION linear_f ( i : SIGNED; max : INTEGER) RETURN  SIGNED IS
	BEGIN
		IF (i < to_signed(max, i'LENGTH)) THEN
			IF (abs(i) < to_signed(max, i'LENGTH)) THEN
				return i;
			ELSE
				return to_signed(max*(-1), i'LENGTH);
			END IF;
		ELSE
			return to_signed(max, i'LENGTH);
		END IF;
	END FUNCTION;

	FUNCTION leaky_relu_f ( i : INTEGER; max : INTEGER; max_bits : INTEGER) RETURN  INTEGER IS
		VARIABLE i_reg : INTEGER range (-1)*(2**max_bits-1) to (2**max_bits-1);
	BEGIN
		IF (i > 0) THEN
			IF (i < max) THEN
				return i;
			ELSE
				return max;
			END IF;
		ELSE
			i_reg := to_integer(shift_right(to_signed(i * leaky_relu_mult, max_bits+CNN_Weight_Resolution-1), CNN_Weight_Resolution-1));
			IF (i_reg > max*(-1)) THEN
				return i_reg;
			ELSE
				return max*(-1);
			END IF;
		END IF;
	END FUNCTION;

	FUNCTION leaky_relu_f ( i : SIGNED; max : INTEGER; max_bits : INTEGER) RETURN  SIGNED IS
		VARIABLE i_reg : SIGNED (max_bits-1 downto 0);
	BEGIN
		IF (i > 0) THEN
			IF (i < to_signed(max, i'LENGTH)) THEN
				return i;
			ELSE
				return to_signed(max, i'LENGTH);
			END IF;
		ELSE
			i_reg := resize(shift_right(resize(i, max_bits+CNN_Weight_Resolution-1) * to_signed(leaky_relu_mult, max_bits+CNN_Weight_Resolution-1), CNN_Weight_Resolution-1), max_bits);
			IF (i_reg > to_signed(max*(-1), i'LENGTH)) THEN
				return i_reg;
			ELSE
				return to_signed(max*(-1), i'LENGTH);
			END IF;
		END IF;
	END FUNCTION;

	FUNCTION step_f ( i : INTEGER) RETURN  INTEGER IS
	BEGIN
		IF (i >= 0) THEN
			return 2**(CNN_Weight_Resolution-1);
		ELSE
			return 0;
		END IF;
	END FUNCTION;

	FUNCTION step_f ( i : SIGNED) RETURN  SIGNED IS
	BEGIN
		IF (i >= 0) THEN
			return to_signed(2**(CNN_Weight_Resolution-1), i'LENGTH);
		ELSE
			return to_signed(0, i'LENGTH);
		END IF;
	END FUNCTION;

	FUNCTION sign_f ( i : INTEGER) RETURN  INTEGER IS
	BEGIN
		IF (i > 0) THEN
			return 2**(CNN_Weight_Resolution-1);
		ELSIF (i < 0) THEN
			return (2**(CNN_Weight_Resolution-1))*(-1);
		ELSE
			return 0;
		END IF;
	END FUNCTION;

	FUNCTION sign_f ( i : SIGNED) RETURN  SIGNED IS
	BEGIN
		IF (i > 0) THEN
			return to_signed(2**(CNN_Weight_Resolution-1), i'LENGTH);
		ELSIF (i < 0) THEN
			return to_signed((2**(CNN_Weight_Resolution-1))*(-1), i'LENGTH);
		ELSE
			return to_signed(0, i'LENGTH);
		END IF;
	END FUNCTION;

	FUNCTION Bool_Select ( Sel : BOOLEAN; Value : NATURAL; Alternative : NATURAL) RETURN  NATURAL IS
	BEGIN
		IF (Sel) THEN
			return Value;
		ELSE
			return Alternative;
		END IF;
	END FUNCTION;

	FUNCTION shift_with_rounding( value : SIGNED; shift_amount : INTEGER) RETURN SIGNED IS
		VARIABLE result      : SIGNED(value'range);
		VARIABLE round_const : SIGNED(value'range);
	BEGIN
		IF shift_amount <= 0 THEN
			return shift_left(value, abs(shift_amount));
		ELSIF shift_amount < value'length THEN
			IF CNN_Efficient_Rounding THEN
				result := shift_right(shift_right(value, shift_amount - 1) + to_signed(1, value'length),1);
			ELSE
				round_const := to_signed(2 ** (shift_amount - 1), value'length);
				result := shift_right(value + round_const, shift_amount);  -- arithmetic shift
			END IF;
			return result;
		ELSE
			IF value(value'high) = '0' THEN
				return (value'range => '0');
			ELSE
				return (value'range => '1');
			END IF;
		END IF;
	END FUNCTION;

	FUNCTION shift_with_rounding( value : UNSIGNED; shift_amount: INTEGER) return UNSIGNED is
		variable result      : UNSIGNED(value'range);
		variable round_const : UNSIGNED(value'range);
	BEGIN
		IF shift_amount <= 0 THEN
			return shift_left(value, abs(shift_amount));
		ELSIF shift_amount < value'length THEN
			IF CNN_Efficient_Rounding THEN
				result := shift_right(shift_right(value, shift_amount - 1) + to_unsigned(1, value'length),1);
			ELSE
				round_const := to_unsigned(2 ** (shift_amount - 1), value'length);
				result := shift_right(value + round_const, shift_amount);  -- arithmetic shift
			END IF;
			return result;
		ELSE
			return (value'range => '0');
		END IF;
	END FUNCTION;

	FUNCTION shift_bits( value : SIGNED; shift_amount : INTEGER) RETURN SIGNED IS
		variable result      : SIGNED(value'range);
		variable intermediate: SIGNED(value'range);
	BEGIN
		IF shift_amount = 0 THEN
			return value;
		ELSIF shift_amount > 0 THEN
			IF shift_amount < value'length THEN
				result := shift_right(value, shift_amount);
			ELSE
				IF value(value'high) = '0' THEN
					result := (value'range => '0');
				ELSE
					result := (value'range => '1');
				END IF;
			END IF;
			return result;
		ELSE
			result := shift_left(value, abs(shift_amount));
			return result;
		END IF;
	END FUNCTION;

	FUNCTION shift_bits( value : UNSIGNED; shift_amount : INTEGER) RETURN UNSIGNED IS
		VARIABLE result      : UNSIGNED(value'range);
		VARIABLE intermediate: UNSIGNED(value'range);
	BEGIN
		IF shift_amount = 0 THEN
			return value;
		ELSIF shift_amount > 0 THEN
			IF shift_amount < value'length THEN
				result := shift_right(value, shift_amount);
			ELSE
				result := (value'range => '0');
			END IF;
			return result;
		ELSE
			result := shift_left(value, abs(shift_amount));
			return result;
		END IF;
	END FUNCTION;

	FUNCTION adjust_offset( value  : INTEGER; offset : INTEGER) RETURN INTEGER IS
		VARIABLE rounded_value : INTEGER;
	BEGIN
		IF offset > 0 THEN
			-- Add 2^(offset-1) before divide to round
			rounded_value := (value + (2 ** (offset - 1)));
			return rounded_value / (2 ** offset);
		ELSIF offset < 0 THEN
			return value * (2 ** (-offset));
		ELSE
			return value;
		END IF;
	END FUNCTION;

	FUNCTION unsigned_multiply_efficient(
		value : NATURAL;
		factor : REAL;
		resolution_val  : NATURAL := CNN_Weight_Resolution-1;
		resolution_fac  : NATURAL := CNN_Weight_Resolution-1
	) RETURN NATURAL IS
		VARIABLE result         : NATURAL range 0 to 2**(resolution_val-1 + 2*resolution_fac);
		VARIABLE n_factor       : UNSIGNED(2*resolution_fac downto 0);
		VARIABLE value_unsigned : UNSIGNED(resolution_val downto 0);
	BEGIN
		value_unsigned := to_unsigned(value, resolution_val+1);
		IF log2(factor) - floor(log2(factor)) = 0.0 THEN                        -- if factor of 2
			result := to_integer(shift_bits(value_unsigned, INTEGER(log2(factor))));    -- do simple shift
		ELSE -- do it the hard way
			n_factor := to_unsigned(INTEGER(factor * REAL(2 ** (CNN_Weight_Resolution-1))), 2*resolution_fac + 1); -- shift left
			result := to_integer(shift_right(value_unsigned * n_factor, CNN_Weight_Resolution-1)); -- multiply and shift back
		END IF;
		return result;--(CNN_Value_Resolution + resolution downto 0);
	END FUNCTION;

END PACKAGE BODY;