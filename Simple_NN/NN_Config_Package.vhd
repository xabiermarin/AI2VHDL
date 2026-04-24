
library IEEE;  
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all; 
use IEEE.math_real.all;

PACKAGE NN_Config_Package is
	CONSTANT NN_Value_Resolution        : NATURAL := 16; -- Precisión numérica de las activaciones (INT16)
	CONSTANT NN_Weight_Resolution       : NATURAL := 16; -- Precisión numérica de los pesos (INT16)
	CONSTANT NN_Parameter_Resolution    : NATURAL := 16; -- Precisión numérica de los parámetros (INT16)
	CONSTANT NN_Input_Size              : NATURAL := 1;  -- nº de entradas (ej: 28x28 aplanado = 784)
	CONSTANT NN_Max_Neurons             : NATURAL := 8;  -- nº máximo de neuronas en cualquier capa
	CONSTANT NN_Value_Negative         : NATURAL := 0;   -- Controla si los valores de activación pueden ser negativos (1) o no (0) --> ReLU (0) | Linear / Leaky ReLU (1)
	CONSTANT NN_Mult_Sum_Group         : INTEGER := 1;  -- Algunos DSPs pueden hacer varias multiplicaciones y acumularlas en una sola operación (con valor 1 cada multiplicación por separado) 
	CONSTANT NN_Shift_Before_Sum       : BOOLEAN := False; -- Controla cuando se hace el desplazamiento de bits (división por potencia de 2) durante la acumulación --> False: Despues de sumar todo (preciso) | True: Desplaza antes (ahorra lógica pero introduce error de redondeo y reduce f_max)
														 	
	subtype NN_Value_T is INTEGER range (-1)*(2**(NN_Value_Resolution-1)-1) to 2**(NN_Value_Resolution-1)-1; -- Tipo base de una sola activación
	type NN_Values_T         is array (NATURAL range <>) of NN_Value_T;  -- Vector de activaciones (Array 1D)

	CONSTANT NN_Sum_Offset             : NATURAL := 4; -- Añadir mas bits a la acumulación de la suma para evitar desbordamiento
	CONSTANT NN_Rounding               : STD_LOGIC_VECTOR := "111"; -- Activa (1) o desactiva (0) redondeo en --> 1. Bit: cada suma parcial, 2. Bit: división de la suma, 3. Bit: resultado tras añadir bias | "111" (Mejor precisión) / "000" (Más rápido)
	CONSTANT NN_Efficient_Rounding     : BOOLEAN := True; -- Elige entre dos metodos de redondeo --> False: metodo estandar (suma de constantes antes del shift) | True: truco de shift que consume menos lógica (mejor para red densa)

	subtype NN_Weight_T      is INTEGER range (-1)*(2**(NN_Weight_Resolution-1)-1) to 2**(NN_Weight_Resolution-1)-1; -- Tipo base para un peso
	type NN_Weights_T        is array (NATURAL range <>, NATURAL range <>) of NN_Weight_T; -- Matriz de pesos (neurona_destino, neurona origen) (Array 2D)

	subtype NN_Parameter_T      is INTEGER range (-1)*(2**(NN_Parameter_Resolution-1)-1) to 2**(NN_Parameter_Resolution-1)-1; -- Tipo base para parámetros como bias
	type NN_Parameters_T        is array (NATURAL range <>) of NN_Parameter_T; -- Vector de bias (Array 1D) (No se utiliza porque el bias se incluye en NN_Weights_T)

	TYPE NN_Stream_T IS RECORD
		Index      : NATURAL range 0 to NN_Input_Size-1; -- Elemento del vector de entrada que se está enviando en un ciclo
		Data_Valid : STD_LOGIC;
		Data_CLK   : STD_LOGIC;
	END RECORD NN_Stream_T;

	type Activation_T is (relu, linear, leaky_relu, step_func, sign_func); --Lista de funciones de activación disponibles

	CONSTANT leaky_relu_mult : NN_Weight_T := (2**(NN_Weight_Resolution-1))/10; -- Pendiente de la parte negativa de la función Leaky Relu (Representación en punto fijo)

	FUNCTION max_val ( a : INTEGER; b : INTEGER) RETURN  INTEGER;       -- Devuelve el mayor de dos enteros
	FUNCTION min_val ( a : INTEGER; b : INTEGER) RETURN  INTEGER;       -- Devuelve el menor de dos enteros
	FUNCTION relu_f ( i : INTEGER; max : INTEGER) RETURN  INTEGER;      -- Función de activación ReLU (integer)
	FUNCTION relu_f ( i : SIGNED; max : INTEGER) RETURN  SIGNED;		-- Función de activación ReLU (signed)
	FUNCTION linear_f ( i : INTEGER; max : INTEGER) RETURN  INTEGER;	-- Función de activación Linear (integer)
	FUNCTION linear_f ( i : SIGNED; max : INTEGER) RETURN  SIGNED;		-- Función de activación Linear (signed)
	FUNCTION leaky_relu_f ( i : INTEGER; max : INTEGER; max_bits : INTEGER) RETURN  INTEGER; -- Función de activación Leaky ReLU (integer)
	FUNCTION leaky_relu_f ( i : SIGNED; max : INTEGER; max_bits : INTEGER) RETURN  SIGNED;   -- Función de activación Leaky ReLU (signed)
	FUNCTION step_f ( i : INTEGER) RETURN  INTEGER;						-- Función de activación step (integer)
	FUNCTION step_f ( i : SIGNED) RETURN  SIGNED;						-- Función de activación step (signed)
	FUNCTION sign_f ( i : INTEGER) RETURN  INTEGER;						-- Función de activación sign (integer)
	FUNCTION sign_f ( i : SIGNED) RETURN  SIGNED;						-- Función de activación sing (signed)
	FUNCTION Bool_Select ( Sel : BOOLEAN; Value  : NATURAL; Alternative : NATURAL) RETURN  NATURAL;	-- Multiplexor condicional: Sel Verdadero -> Devuelve Value | Sel Falso -> Devuelve Alternative
	FUNCTION shift_with_rounding(value : SIGNED; shift_amount: INTEGER) RETURN SIGNED;		-- Desplazamiento de bits con rendondeo (integer)
	FUNCTION shift_with_rounding(value : UNSIGNED; shift_amount: INTEGER) RETURN UNSIGNED;	-- Desplazamiento de bits con rendondeo (signed)
	FUNCTION shift_bits(value : SIGNED; shift_amount: INTEGER) RETURN SIGNED;		-- Desplazamiento de bits sin rendondeo (integer)
	FUNCTION shift_bits(value : UNSIGNED; shift_amount: INTEGER) RETURN UNSIGNED;	-- Desplazamiento de bits sin rendondeo (signed)
	FUNCTION adjust_offset(value : INTEGER; offset : INTEGER) RETURN INTEGER;		-- Ajusta un valor aplicando un offset de bits (usado para alinear la coma decimal en punto fijo)
	FUNCTION unsigned_multiply_efficient(value : NATURAL; factor: REAL; resolution_val : NATURAL := NN_Weight_Resolution-1; resolution_fac : NATURAL := NN_Weight_Resolution-1) RETURN NATURAL; -- Multiplica un valor natural por un factor real de forma eficiente en hardware, usando shifts cuando el factor es potencia de 2 y multiplicación cuando no lo es

END PACKAGE NN_Config_Package;

PACKAGE BODY NN_Config_Package IS
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
			i_reg := to_integer(shift_right(to_signed(i * leaky_relu_mult, max_bits+NN_Weight_Resolution-1), NN_Weight_Resolution-1));
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
			i_reg := resize(shift_right(resize(i, max_bits+NN_Weight_Resolution-1) * to_signed(leaky_relu_mult, max_bits+NN_Weight_Resolution-1), NN_Weight_Resolution-1), max_bits);
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
			return 2**(NN_Weight_Resolution-1);
		ELSE
			return 0;
		END IF;
	END FUNCTION;

	FUNCTION step_f ( i : SIGNED) RETURN  SIGNED IS
	BEGIN
		IF (i >= 0) THEN
			return to_signed(2**(NN_Weight_Resolution-1), i'LENGTH);
		ELSE
			return to_signed(0, i'LENGTH);
		END IF;
	END FUNCTION;

	FUNCTION sign_f ( i : INTEGER) RETURN  INTEGER IS
	BEGIN
		IF (i > 0) THEN
			return 2**(NN_Weight_Resolution-1);
		ELSIF (i < 0) THEN
			return (2**(NN_Weight_Resolution-1))*(-1);
		ELSE
			return 0;
		END IF;
	END FUNCTION;

	FUNCTION sign_f ( i : SIGNED) RETURN  SIGNED IS
	BEGIN
		IF (i > 0) THEN
			return to_signed(2**(NN_Weight_Resolution-1), i'LENGTH);
		ELSIF (i < 0) THEN
			return to_signed((2**(NN_Weight_Resolution-1))*(-1), i'LENGTH);
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
			IF NN_Efficient_Rounding THEN
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
		VARIABLE result      : UNSIGNED(value'range);
		VARIABLE round_const : UNSIGNED(value'range);
	BEGIN
		IF shift_amount <= 0 THEN
			return shift_left(value, abs(shift_amount));
		ELSIF shift_amount < value'length THEN
			IF NN_Efficient_Rounding THEN
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
		VARIABLE result      : SIGNED(value'range);
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
		resolution_val  : NATURAL := NN_Weight_Resolution-1;
		resolution_fac  : NATURAL := NN_Weight_Resolution-1
	) RETURN NATURAL IS
		VARIABLE result         : NATURAL range 0 to 2**(resolution_val-1 + 2*resolution_fac);
		VARIABLE n_factor       : UNSIGNED(2*resolution_fac downto 0);
		VARIABLE value_unsigned : UNSIGNED(resolution_val downto 0);
	BEGIN
		value_unsigned := to_unsigned(value, resolution_val+1);
		IF log2(factor) - floor(log2(factor)) = 0.0 THEN	-- Si es factor de 2
			result := to_integer(shift_bits(value_unsigned, INTEGER(log2(factor))));	-- Shift simple
		ELSE	-- Si no es factor de 2
			n_factor := to_unsigned(INTEGER(factor * REAL(2 ** (NN_Weight_Resolution-1))), 2*resolution_fac + 1); -- Convierte factor real a punto fijo y hace shift a izquierda
			result := to_integer(shift_right(value_unsigned * n_factor, NN_Weight_Resolution-1));	-- Multiplica y desplaza de vuelta a la derecha
		END IF;
		return result;
	END FUNCTION;

END PACKAGE BODY;