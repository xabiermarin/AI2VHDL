
-- Descripción: Este componente calcula las salidas de una capa de densa de una red neuronal
-- Insertion:   Especifica los parámetros con las contantes del archivo NN_Data
--              Conecta las señales Cycle_Reg data y stream con el Cycle_Reg o la capa anterior

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.NN_Config_Package.all;
use work.NN_Data_Package.all;

ENTITY NN_Layer IS
    GENERIC (
        Inputs          : NATURAL := 16; -- Número de inputs
        Outputs         : NATURAL := 8;  -- Número de outpus
        Activation      : Activation_T := relu; -- Función de activacion
        Input_Cycles    : NATURAL := 1;  -- Controla en cuantos ciclos entra la información a la capa. Tiene que ser un divisor del numero de entradas
        Calc_Cycles     : NATURAL := 1;  -- Controla en cuantos ciclos se realizan los cálculos en la capa
        Output_Cycles   : NATURAL := 1;  -- Controla en cuantos ciclos sale la información de la capa
        Output_Delay    : NATURAL := 1;  -- Añade ciclos de espera entre valores de salida (útil para sincronización de capas)
        Offset_In       : INTEGER := 0;  -- Desplazamiento de la coma decimal en punto fijo en los datos de entrada
        Offset_Out      : INTEGER := 0;  -- Desplazamiento de la coma decimal en punto fijo en los datos de salida
        Offset          : INTEGER := 0;  -- Despalzamiento de la coma decimal en punto fijo de los pesos almacenados en la ROM
        Weights         : NN_Weights_T   -- Matriz de pesos de la capa (almacenado en NN_Data_Package)
    );
    PORT (
        iStream : IN  NN_Stream_T;  -- Stream de control con Index, Data_Valid y Data_Clk
        iData   : IN  NN_Values_T(Inputs/Input_Cycles-1 downto 0);  -- Vector de activaciones
        iCycle  : IN  NATURAL range 0 to Input_Cycles-1;  -- Ciclo de cálculo
        
        oStream : OUT NN_Stream_T;  -- Stream de control con Index, Data_Valid y Data_Clk
        oData   : OUT NN_Values_T(Outputs/Output_Cycles-1 downto 0) := (others => 0);   -- Vector de activaciones
        oCycle  : OUT NATURAL range 0 to Output_Cycles-1    -- Ciclo de cálculo
    );
END NN_Layer;

ARCHITECTURE BEHAVIORAL OF NN_Layer IS
    CONSTANT Calc_Outputs  : NATURAL := Outputs/Calc_Cycles;   -- Cuantas neuronas de salida se calculan en paralelo por ciclo
    CONSTANT Calc_Steps    : NATURAL := Inputs/Input_Cycles;   -- Cuantas entradas (Cycle_Reg) se procesan a la vez
    CONSTANT Out_Values    : NATURAL := Outputs/Output_Cycles; -- Cuantos valores de salida se envian a la vez al siguiente componente
    CONSTANT Offset_Diff   : INTEGER := Offset_Out-Offset_In;  -- Diferencia relativa entre el offset de salida y entrada (usado para ajustar la escala entre capas)
    
    CONSTANT Bias_Offset            : INTEGER := Offset_In-Offset-NN_Sum_Offset;  -- Desplazamiento bruto necesario para alinear el bias con la suma acumulada
    CONSTANT Bias_Offset_Fixed      : INTEGER := max_val(Bias_Offset, 0);         -- Recorta el offset a mínimo 0 (porque desplazamiento negativo aquí no tiene sentido)
    CONSTANT Sum_Offset_Bias        : INTEGER := Bias_Offset_Fixed-Bias_Offset;   -- Cuanto hay que desplazar la suma antes de añadir el bias para que estén en la misma escala
    CONSTANT Bias_Offset_Correction : INTEGER := NN_Sum_Offset - Sum_Offset_Bias; -- Calcula la correción restante que hay que aplicar despues de sumar el bias

    -- ============================================================================
    -- Extaer el bias de la matriz de peso y guardar por separado aplicando offset 
    -- ============================================================================ 
    FUNCTION Init_Bias ( weights_in : NN_Weights_T; neurons : NATURAL; inputs : NATURAL; Offset_In : INTEGER) RETURN  NN_Parameters_T IS
        VARIABLE Bias_Const : NN_Parameters_T(0 to neurons-1);
    BEGIN
        FOR i in 0 to neurons-1 LOOP
            Bias_Const(i) := adjust_offset(weights_in(i,inputs), Bias_Offset_Fixed);
        END LOOP;
        
        return Bias_Const;  
    END FUNCTION;

    CONSTANT Bias_Const : NN_Parameters_T(0 to Outputs-1) := Init_Bias(Weights, Outputs, Inputs, Offset_In); -- Vector de bias


    type ROM_Array is array (0 to Calc_Cycles*Input_Cycles-1) of STD_LOGIC_VECTOR(Calc_Outputs * Calc_Steps * NN_Weight_Resolution - 1 downto 0); -- Define cómo se organiza la ROM en hardware. Array donde cada  posición contiene un vector de bits que agrupa todos los pesos necesarios para un ciclo de cálculo

    -- ==============================================================================================
    -- Guardar los pesos en una ROM en base al número de pesos que se necesitan por ciclo de cálculo
    -- ==============================================================================================
    FUNCTION Init_ROM ( weights_in : NN_Weights_T; neurons : NATURAL; inputs : NATURAL; elements : NATURAL; calc_neurons : NATURAL; calc_steps : NATURAL) RETURN  ROM_Array IS
        VARIABLE rom_reg : ROM_Array;
        VARIABLE neurons_cnt : NATURAL range 0 to neurons := 0;
        VARIABLE inputs_cnt  : NATURAL range 0 to inputs := 0;
        VARIABLE element_cnt : NATURAL range 0 to elements := 0;
        VARIABLE this_weight : STD_LOGIC_VECTOR(NN_Weight_Resolution-1 downto 0);
    BEGIN
        neurons_cnt := 0;
        inputs_cnt  := 0;
        element_cnt := 0;
        WHILE inputs_cnt < inputs LOOP
            neurons_cnt := 0;
            WHILE neurons_cnt < neurons LOOP
                FOR s in 0 to calc_steps-1 LOOP
                    FOR f in 0 to calc_neurons-1 LOOP
                        this_weight :=  STD_LOGIC_VECTOR(TO_SIGNED(weights_in(neurons_cnt+f, inputs_cnt+s), NN_Weight_Resolution));
                        rom_reg(element_cnt)(NN_Weight_Resolution*(1+s*calc_neurons+f)-1 downto NN_Weight_Resolution*(s*calc_neurons+f)) := this_weight;
                    END LOOP;
                END LOOP;
                neurons_cnt := neurons_cnt + calc_neurons;
                element_cnt := element_cnt + 1;
            END LOOP;
            inputs_cnt  := inputs_cnt + calc_steps;
        END LOOP;
        
        return rom_reg;
    END FUNCTION;

    -- ROM para guardar los pesos
    SIGNAL ROM : ROM_Array := Init_ROM(Weights, Outputs, Inputs, Calc_Cycles*Input_Cycles, Calc_Outputs, Calc_Steps);   -- Señal que almacena la ROM inicializada con Init_ROM
    SIGNAL ROM_Addr  : NATURAL range 0 to Calc_Cycles*Input_Cycles-1;   -- Direccion de ROM por ciclo
    SIGNAL ROM_Data  : STD_LOGIC_VECTOR(Calc_Outputs * Calc_Steps * NN_Weight_Resolution - 1 downto 0); -- Dato leido de la ROM por ciclo

    CONSTANT value_max     : NATURAL := 2**(NN_Value_Resolution-1)-1;   -- Valor máximo representable con la resolución configurada
    CONSTANT bits_max      : NATURAL := NN_Value_Resolution - 1 + max_val(Offset, 0) + integer(ceil(log2(real(Inputs + 1))));   -- Cuantos bits necesita el acumulador interno para no desborarse durante la suma de todos los procesos peso*entrada

    -- RAM para cuando el cálculo se divide en múltiples ciclos
    type sum_set_t is array (0 to Calc_Outputs-1) of SIGNED(bits_max downto 0); -- Array que contiene las sumas parciales de todas las neuronas que se calculan en paralelo en un ciclo
    type sum_ram_t is array (natural range <>) of sum_set_t;    -- Array de sum_set_t. Una entrada por cada ciclo de cálculo
    SIGNAL SUM_RAM : sum_ram_t(0 to Calc_Cycles-1) := (others => (others => (others => '0')));
    SIGNAL SUM_Rd_Addr  : NATURAL range 0 to Calc_Cycles-1;     -- Puerto de dirección de lectura
    SIGNAL SUM_Rd_Data  : sum_set_t;                            -- Puerto de datos de lectura
    SIGNAL SUM_Wr_Addr  : NATURAL range 0 to Calc_Cycles-1;     -- Puerto de dirección de escritura
    SIGNAL SUM_Wr_Data  : sum_set_t;                            -- Puerto de datos de escritura
    SIGNAL SUM_Wr_Ena   : STD_LOGIC := '1';                     -- Puerto de habilitar escritura

    -- RAM que almacena los valores de salida ya activados antes de enviarlos a la siguiente capa
    CONSTANT OUT_RAM_Elements : NATURAL := min_val(Calc_Cycles, Output_Cycles);  -- Número de entradas de la RAM (Mínimo entre Calc_Cycles y Output_Cycles para usar la menor memoria posible)
    type OUT_set_t is array (0 to Outputs/OUT_RAM_Elements-1) of SIGNED(NN_Value_Resolution-1 downto 0);    -- Array de valores de salida que se escriben juntos en un ciclo
    type OUT_ram_t is array (natural range <>) of OUT_set_t;    -- Array de OUT_set_t. Una entrada por cada ciclo de cálculo
    SIGNAL OUT_RAM      : OUT_ram_t(0 to OUT_RAM_Elements-1) := (others => (others => (others => '0')));
    SIGNAL OUT_Rd_Addr  : NATURAL range 0 to OUT_RAM_Elements-1;    -- Puerto de dirección de lectura
    SIGNAL OUT_Rd_Data  : OUT_set_t;                                -- Puerto de datos de lectura
    SIGNAL OUT_Wr_Addr  : NATURAL range 0 to OUT_RAM_Elements-1;    -- Puerto de dirección de escritura
    SIGNAL OUT_Wr_Data  : OUT_set_t;                                -- Puerto de datos de escritura
    SIGNAL OUT_Wr_Ena   : STD_LOGIC := '1';                         -- Puerto de habilitar escritura
    
    -- Señales de control
    SIGNAL Calc_En           : BOOLEAN := false;  -- Indica que hay un cálculo en curso
    SIGNAL Calc_En_Sum       : BOOLEAN := false;  -- Indica que el cálculo de la suma de la red neuronal está en curso
    SIGNAL Output_Bias_Reg   : NATURAL range 0 to Calc_Cycles := 0; -- Lleva la cuenta de a qué neurona se le está añadiendo el bias
    SIGNAL Add_Bias          : BOOLEAN := false;  -- Indica que la suma se ha calculado y que se puede añadir el bias
    SIGNAL Last_Input        : STD_LOGIC;         -- Indica que el cálculo ha finalizado y la salida se puede enviar a la siguiente capa
    SIGNAL Out_Cycle_Cnt_Reg : NATURAL range 0 to Output_Cycles-1 := Output_Cycles-1;  -- Salida actual que lleva un ciclo de retraso, por lo que se puede leer de la RAM
    SIGNAL Out_Delay_Cnt     : NATURAL range 0 to Output_Delay-1 := Output_Delay-1;    -- Contador para retrasar los valores de salida que se envian uno tras otro
    SIGNAL Out_Ready         : STD_LOGIC;  -- Verdarero si los datos de salida se pueden leer de la RAM

    SIGNAL iData_Reg         : NN_Values_T(Inputs/Input_Cycles-1 downto 0); -- Registra los datos de entrada un ciclo para que estén disponibles cuando se cargan los pesos de la ROM 

    -- Constantes de agrupación de productos
    CONSTANT Group_Sum_Results    : NATURAL := INTEGER(ceil(REAL(Calc_Steps) / REAL(NN_Mult_Sum_Group))); -- Cuantos grupos de productos hay
    CONSTANT Real_Group_Sum_Size  : NATURAL := Calc_Steps / Group_Sum_Results;  -- Tamaño real de cada grupo tras la división
    CONSTANT Group_Sum_Bits       : NATURAL := INTEGER(ceil(log2(REAL(Real_Group_Sum_Size)))); -- Bits extra necesarios para acumular dentro de un grupo sin desbordamiento
    CONSTANT Group_Sum_Total_Bits : NATURAL := Bool_Select(NN_Shift_Before_Sum, bits_max+1, NN_Value_Resolution + NN_Weight_Resolution -1) + Group_Sum_Bits; -- Ancho total de cada producto agrupado 
    type prod_array_t is array (0 to Calc_Outputs-1, 0 to Group_Sum_Results-1) of SIGNED(Group_Sum_Total_Bits-1 downto 0); -- Buffer 2D que almacena los productos intermedios entre un ciclo de reloj y el siguiente
    signal Prod_Buf   : prod_array_t := (others => (others => (others =>'0'))); -- Buffer 2D donde se guardan los productos agrupados, una entrada por neurona y grupo
    SIGNAL SUM_Rd_Addr_Reg  : NATURAL range 0 to Calc_Cycles-1; -- Registro con un con un ciclo de retraso de la dirección de lectura de la RAM

BEGIN
    oStream.Data_CLK <= iStream.Data_CLK;

    -- =============================
    -- Proceso de lecutra de la ROM
    -- =============================
    --  En cada flanco de subida del reloj lee la posición ROM_Addr de la ROM y la coloca en ROM_Data
    PROCESS (iStream)
    BEGIN
        IF (rising_edge(iStream.Data_CLK)) THEN
            ROM_Data <= ROM(ROM_Addr);
        END IF;
    END PROCESS;
    
    -- ===============================================
    -- Proceso de escritura síncrona de la RAM de suma
    -- ===============================================
    -- Escribe en la RAM de suma cuando SUM_Wr_Ena está activo
    PROCESS (iStream)
    BEGIN
        IF (rising_edge(iStream.Data_CLK)) THEN
            IF (SUM_Wr_Ena = '1') THEN
                SUM_RAM(SUM_Wr_Addr) <= SUM_Wr_Data;
            END IF;
        END IF;
    END PROCESS;
      
    SUM_Rd_Data <= SUM_RAM(SUM_Rd_Addr);  -- Lectura combinacional (asíncrona) de la  RAM
    
    -- =================================================
    -- Proceso de escritura síncrona de la RAM de salida
    -- =================================================
    -- Escribe en la RAM de suma cuando OUT_Wr_Ena está activo
    PROCESS (iStream)
    BEGIN
        IF (rising_edge(iStream.Data_CLK)) THEN
            IF (OUT_Wr_Ena = '1') THEN
                OUT_RAM(OUT_Wr_Addr) <= OUT_Wr_Data;
            END IF;
        END IF;
    END PROCESS;
    
    OUT_Rd_Data <= OUT_RAM(OUT_Rd_Addr); -- Lectura combinacional (asíncrona) de la  RAM
       
    PROCESS (iStream)
    -- Variables del proceso principal    
    
    -- Variables para seguimiento del cálculo actual
        VARIABLE Cycle_Reg     : NATURAL range 0 to Input_Cycles-1;                  -- Lleva la cuenta del ciclo de entrada actual
        VARIABLE Cycle_Reg_2   : NATURAL range 0 to Input_Cycles-1;                  -- Version con un ciclo de retraso de Cycle_Reg
        VARIABLE Output_Cnt    : NATURAL range 0 to Calc_Cycles := 0;                -- Cuenta qué grupo de neuronas de salida se están calculando actualmente
        VARIABLE Output_Cnt_2  : NATURAL range 0 to Calc_Cycles := 0;                -- Version con un ciclo de retraso de Output_Cnt
        VARIABLE Element_Cnt   : NATURAL range 0 to Calc_Cycles*Input_Cycles-1 := 0; -- Cuenta el paso global del cálculo combinado de ciclos de entrada
        VARIABLE Element_Reg   : NATURAL range 0 to Calc_Cycles*Input_Cycles-1 := 0; -- Cuenta el paso global del cálculo combinado de ciclos de salida
        
        VARIABLE Weights_Buf : NN_Weights_T(0 to Calc_Outputs-1, 0 to Calc_Steps-1); -- Buffer local donde se desempaquetan los pesos leídos de la ROM para poder acceder a ellos por índice de neurona y entrada
        
        -- Variables para escribir las salida calculadas en la RAM de salida
        type     Act_sum_t is array (Calc_Outputs-1 downto 0) of SIGNED(NN_Value_Resolution-1 downto 0); -- Array para almacenar las activaciones ya calculadas 
        VARIABLE Act_sum : Act_sum_t;   -- Almacena las activaciones ya calculadas antes de escribirlas en la RAM de salida
        CONSTANT Act_sum_buf_cycles : NATURAL := Calc_Cycles/OUT_RAM_Elements;  -- Buffer adicional para cuando hay que acumulas varios ciclos de cálculo antes de escribir en la RAM
        type     Act_sum_buf_t is array (Act_sum_buf_cycles-1 downto 0) of Act_sum_t;  -- Array para almacenar las activaciones ya calculadas 
        VARIABLE Act_sum_buf     : Act_sum_buf_t;   -- Almacena las activaciones ya calculadas antes de escribirlas en la RAM de salida
        VARIABLE Act_sum_buf_cnt : NATURAL range 0 to Act_sum_buf_cycles-1 := 0;  -- Buffer adicional para cuando hay que acumulas varios ciclos de cálculo antes de escribir en la RAM
        
        VARIABLE Out_Cycle_Cnt : NATURAL range 0 to Output_Cycles-1 := Output_Cycles-1;  -- Cuenta que ciclo de salida en que ciclo de salida se está enviando datos a la siguiente capa
        
        -- Suma actual durante el cálculo
        VARIABLE sum : sum_set_t := (others => (others => '0'));            -- Suma acumulada actual (Se le van sumando productos cada ciclo)
        VARIABLE Sum_Reg    : sum_set_t := (others => (others => '0'));     -- Copia registrada en el momento de añadir el bias (Valor de sum al registrar útlima entrada)
        
        VARIABLE Group_Sum_Cnt  : NATURAL range 0 to Real_Group_Sum_Size := 0;  -- Cuenta cuántos productos se han acumulado en Prod_Sum_Buf dentro del grupo actual
        VARIABLE Prod_Sum_Cnt      : NATURAL range 0 to Group_Sum_Results := 0;    --cuenta en qué grupo se está trabajando, para saber en qué posición de Prod_Buf guardar el resultado cuando el grupo esté completo
        VARIABLE Prod_Sum_Buf       : SIGNED(Group_Sum_Total_Bits-1 downto 0);      -- Acumulador temporal donde se van sumando los productos de un mismo grupo antes de guardarse en Prod_Buf
    
        BEGIN
        IF (rising_edge(iStream.Data_CLK)) THEN
            Calc_En_Sum <= Calc_En;  -- Retrasa la señal de habilitación un ciclo, creando el pipeline entre la multiplicación y la suma 
            
            Last_Input <= '0';      -- Reset
            Add_Bias   <= false;    -- Reset
            
            -- Desempaquetar los pesos de ROM_Data en Weights_Buf (Variable con datatype NN_Weight)
            FOR s in 0 to Calc_Steps-1 LOOP
                FOR f in 0 to Calc_Outputs-1 LOOP
                    Weights_Buf(f, s) := TO_INTEGER(SIGNED(ROM_Data(NN_Weight_Resolution * (1 + s * Calc_Outputs+f)-1 downto NN_Weight_Resolution * (s * Calc_Outputs + f))));
                END LOOP;
            END LOOP;
            

            -- Añadir bias, aplicar función de activación y escribir en OUT RAM
            IF (Add_Bias) THEN
                FOR o in 0 to Calc_Outputs-1 LOOP
                    -- Añadir el bias con el offset de los pesos
                    IF NN_Rounding(1) = '1' THEN
                        Sum_Reg(o) := resize(shift_with_rounding(Sum_Reg(o), Sum_Offset_Bias) + to_signed(Bias_Const(o + Output_Bias_Reg * Calc_Outputs), bits_max+1),bits_max+1);
                    ELSE
                        Sum_Reg(o) := resize(shift_bits(Sum_Reg(o), Sum_Offset_Bias) + to_signed(Bias_Const(o + Output_Bias_Reg * Calc_Outputs), bits_max+1),bits_max+1);
                    END IF;

                    -- Ajustar el offset de salida
                    IF NN_Rounding(2) = '1' THEN
                        Sum_Reg(o) := shift_with_rounding(Sum_Reg(o), Offset_Diff + Bias_Offset_Correction);
                    ELSE
                        Sum_Reg(o) := shift_bits(Sum_Reg(o), Offset_Diff + Bias_Offset_Correction);
                    END IF;
                    
                    -- Aplicar la función de activación
                    IF (Activation = relu) THEN
                        Act_sum(o) := resize(relu_f(Sum_Reg(o), value_max), NN_Value_Resolution);
                    ELSIF (Activation = linear) THEN
                        Act_sum(o) := resize(linear_f(Sum_Reg(o), value_max), NN_Value_Resolution);
                    ELSIF (Activation = leaky_relu) THEN
                        Act_sum(o) := resize(leaky_relu_f(Sum_Reg(o), value_max, NN_Value_Resolution + max_val(Offset, 0) + integer(ceil(log2(real(Inputs + 1))))), NN_Value_Resolution);
                    ELSIF (Activation = step_func) THEN
                        Act_sum(o) := resize(step_f(Sum_Reg(o)), NN_Value_Resolution);
                    ELSIF (Activation = sign_func) THEN
                        Act_sum(o) := resize(sign_f(Sum_Reg(o)), NN_Value_Resolution);
                    END IF;
                END LOOP;
                
                -- Escribir las activaciones calculadas en la RAM de salida (tiene un número fijo de outputs que se envian cada vez)
                IF (Calc_Cycles = OUT_RAM_Elements) THEN  -- Cada grupo de activaciones se escribe directamente en la RAM en su posición correspondiente
                    OUT_Wr_Addr <= Output_Bias_Reg;
                    FOR i in 0 to Calc_Outputs-1 LOOP
                        OUT_Wr_Data(i) <= Act_sum(i);
                    END LOOP;
                ELSE  -- Cuando hay más ciclos de cálculo que entradas de RAM, hay que acumular varios grupos de activaciones en Act_sum_buf antes de escribirlos juntos
                    Act_sum_buf_cnt := Output_Bias_Reg mod Act_sum_buf_cycles;
                    Act_sum_buf(Act_sum_buf_cnt) := Act_sum;
                    IF (Act_sum_buf_cnt = Act_sum_buf_cycles-1) THEN
                        OUT_Wr_Addr <= Output_Bias_Reg/Act_sum_buf_cycles;
                        FOR i in 0 to Act_sum_buf_cycles-1 LOOP
                            FOR j in 0 to Calc_Outputs-1 LOOP
                                OUT_Wr_Data(Calc_Outputs*i + j) <= Act_sum_buf(i)(j);
                            END LOOP;
                        END LOOP;
                    END IF;
                END IF;

                -- Enviar los datos de salida cuando todos los pasos de la red neuronal están hechos
                IF (Output_Bias_Reg = Calc_Cycles-1) THEN  -- Significa que se ha procesado la última neurona
                    Last_Input <= '1';  -- Se activa Last_Input para señalizar que la capa ha terminado su cálculo
                END IF;
            END IF;
            
            -- Acumulación de la suma (Cálculo de la red neuronal)
            IF (Calc_En_Sum) THEN  -- Se ejecuta cuando Calc_En_Sum está activo, es decir un ciclo después de calcular los productos
                -- Carga la útlima suma guardada en la RAM si el cálculo esta dividido en más de un ciclo
                IF (Calc_Cycles > 1) THEN  
                    sum := SUM_Rd_Data;
                END IF;
                
                -- Si es el primer ciclo de entrada se resetea sum
                IF (Cycle_Reg_2 = 0) THEN
                    sum := (others => (others => '0'));
                END IF;
                
                -- Calcula los valores de salida
                FOR o in 0 to Calc_Outputs-1 LOOP
                    FOR i in 0 to Group_Sum_Results-1 LOOP
                        IF NN_Shift_Before_Sum THEN         -- Con True suma directamente Prod_Buf sin desplazar
                            sum(o) := resize(sum(o) + Prod_Buf(o, i), bits_max+1);
                        ELSE
                            IF NN_Rounding(0) = '1' THEN    -- Con False desplaza cada Prod_Buf antes de sumarlo 
                                sum(o) := resize(sum(o) + resize(shift_with_rounding(Prod_Buf(o, i), NN_Weight_Resolution-Offset-1-NN_Sum_Offset),bits_max+1),bits_max+1);
                            ELSE
                                sum(o) := resize(sum(o) + resize(shift_bits(Prod_Buf(o, i), NN_Weight_Resolution-Offset-1-NN_Sum_Offset),bits_max+1),bits_max+1);
                            END IF;
                        END IF;
                    END LOOP;
                END LOOP;
                
                -- Si es el último ciclo de entrada, congela la suma en Sum_Reg y activa Add_Bias para que el bloque anterior añada el bias en el siguiente ciclo
                IF (Cycle_Reg_2 = Input_Cycles-1) THEN
                    Sum_Reg  := sum;
                    Add_Bias <= true;
                END IF;
                
                -- Si el cálculo se divide en varios ciclos, guarda la suma parcial en la RAM
                IF (Calc_Cycles > 1) THEN
                    SUM_Wr_Data <= sum;
                END IF;
                
                -- Guardar el cálculo actual para sumarle el bias
                Output_Bias_Reg  <= Output_Cnt_2;
            END IF;
            
            -- Cálculo de las multiplicaciones (entrada X peso) de la red neuronal
            IF (Calc_En) THEN
                
                -- Cálculo de los valores de salida
                FOR o in 0 to Calc_Outputs-1 LOOP
                    Group_Sum_Cnt := 0;  -- Reset
                    Prod_Sum_Cnt     := 0;  -- Reset
                    Prod_Sum_Buf := (others => '0');  -- Reset
                    FOR i in 0 to Calc_Steps-1 LOOP
                        IF NN_Shift_Before_Sum THEN     -- Con True lo desplaza inmediatamente para reducir bits, y lo acumula en Prod_Sum_Buf
                            IF NN_Rounding(0) = '1' THEN
                                Prod_Sum_Buf := Prod_Sum_Buf + resize(shift_with_rounding(to_signed(iData_Reg(i) * Weights_Buf(o, i), NN_Value_Resolution + NN_Weight_Resolution-1), NN_Weight_Resolution - Offset-1 - NN_Sum_Offset), bits_max+1);
                            ELSE    -- Con False calcula el producto completo sin desplazar y lo acumula directamente 
                                Prod_Sum_Buf := Prod_Sum_Buf + resize(shift_bits(to_signed(iData_Reg(i) * Weights_Buf(o, i), NN_Value_Resolution + NN_Weight_Resolution-1), NN_Weight_Resolution - Offset-1 - NN_Sum_Offset), bits_max+1);
                            END IF;
                        ELSE
                            Prod_Sum_Buf := Prod_Sum_Buf + to_signed(iData_Reg(i) * Weights_Buf(o, i), NN_Value_Resolution + NN_Weight_Resolution-1);
                        END IF;
                        
                        IF i = Calc_Steps-1 THEN  -- Si es el último elemento se guarda la salida
                            Prod_Buf(o, Prod_Sum_Cnt) <= Prod_Sum_Buf;
                        ELSIF Group_Sum_Cnt < Real_Group_Sum_Size-1 THEN    -- Si el grupo no está lleno todavia, se sigue acumulando 
                            Group_Sum_Cnt := Group_Sum_Cnt + 1;
                        ELSE    -- Si el grupo está lleno, se guarada en Prod_Buf y empieza el siguiente
                            Group_Sum_Cnt := 0;
                            
                            Prod_Buf(o, Prod_Sum_Cnt) <= Prod_Sum_Buf;
                            Prod_Sum_Buf := (others => '0');
                            
                            Prod_Sum_Cnt := Prod_Sum_Cnt + 1;
                        END IF;
                    END LOOP;
                END LOOP;
                
            END IF;
            
            -- Actualizar versiones retrasadas de los contadores
            Cycle_Reg_2 := Cycle_Reg;
            Output_Cnt_2 := Output_Cnt;
            
            -- Seguimiento de los pasos del cálculo mientras haya nuevos datos disponibles para el cálculo
            IF (iStream.Data_Valid = '1') THEN
                Calc_En    <= true;     -- Activa el cálculo
                iData_Reg  <= iData;    -- Guarda datos de entrada para el siguiente ciclo
                Output_Cnt := 0;        -- Resetea contador de neuronas de salida
                Cycle_Reg := iCycle;    -- Guarda ciclo de entrada actual
                
                -- Contar los pasos del cálculo
                IF (iCycle = 0) THEN  -- Resetea el contador global al inicio de cada nueva muestra 
                    Element_Cnt := 0;
                ELSIF(element_cnt < Calc_Cycles*Input_Cycles-1) THEN -- Incrementa el contador global si no ha llegado al máximo
                    Element_Cnt := Element_Cnt + 1;
                END IF;
            ELSIF (Output_Cnt < Calc_Cycles-1 and element_cnt < Calc_Cycles*Input_Cycles-1) THEN  --Cuando no hay datos válidos pero el cálculo no ha terminado
            -- Avanza los contadores para procesar los grupos de neuronas restantes
                Output_Cnt  := Output_Cnt + 1;
                Element_Cnt := Element_Cnt + 1;
            ELSE -- Cuando se han procesado todos los grupos 
                Calc_En <= false; -- Se desactiva el cálculo
            END IF;
                
            -- Cargar el último valor calculado en la RAM
            SUM_Wr_Addr <= SUM_Rd_Addr;
            SUM_Rd_Addr <= SUM_Rd_Addr_Reg;
            SUM_Rd_Addr_Reg <= Output_Cnt;
                
            -- Precarga la siguiente dirección de ROM
            IF (iStream.Data_Valid = '1' OR Calc_En) THEN
                IF (Element_Cnt < Calc_Cycles*Input_Cycles-1) THEN
                    ROM_Addr <= Element_Cnt + 1;
                ELSE
                    ROM_Addr <= 0;
                END IF;
            END IF;
            
            -- Indicador de que la salida de la capa está lista: 0 --> No listo | 1 --> Listo 
            Out_Ready <= '0';
                
            -- Count through results of this neural network
            IF (Last_Input = '1') THEN  -- Cuando se preocesa la última salida
                Out_Cycle_Cnt := 0;     -- Reset
                Out_Delay_Cnt <= 0;     -- Reset
                Out_Ready     <= '1';   -- Salida lista
            ELSIF (Out_Delay_Cnt < Output_Delay-1) THEN      -- Sis igue en periodo retardo
                Out_Delay_Cnt <= Out_Delay_Cnt + 1;     -- Avanza el retardo
            ELSIF (Out_Cycle_Cnt_Reg < Output_Cycles-1) THEN -- Retardo completado pero quedan grupos de salida por enviar
                Out_Delay_Cnt <= 0;     -- Reset
                Out_Cycle_Cnt := Out_Cycle_Cnt_Reg + 1; -- Siguiente grupo de salida
                Out_Ready     <= '1';  -- Siguiente salida lista
            END IF;
                
            -- Leer el valor de salida desde la RAM
            Out_Cycle_Cnt_Reg  <= Out_Cycle_Cnt;  -- Registra Out_Cycle_Cnt para compensar la latencia de la RAM de salida
            OUT_Rd_Addr        <= Out_Cycle_Cnt / (Output_Cycles/OUT_RAM_Elements);  -- Calcula la dirección de lectura 
                
            -- Si la salida se ha calculado, se lee la RAM y se establece oStream
            IF (Out_Delay_Cnt = 0) THEN  -- Cuando no hay retardo activo lee los valores de la RAM de salida y los coloca en oData
                FOR i in 0 to Out_Values-1 LOOP
                    IF (Output_Cycles = OUT_RAM_Elements) THEN 
                        oData(i) <= to_integer(OUT_Rd_Data(i));  -- El índice es directo
                    ELSE  
                        oData(i) <= to_integer(OUT_Rd_Data(i+(Out_Cycle_Cnt_Reg mod (Output_Cycles/OUT_RAM_Elements))*Out_Values));  -- Calcula el offset correcto dentro de la entrada de RAM
                    END IF;
                END LOOP;
                
                oCycle             <= Out_Cycle_Cnt_Reg;  -- Indica qué ciclo de salida se está enviando
                oStream.Data_Valid <= Out_Ready;          -- Propaga la señal de dato válido
            ELSE
                oStream.Data_Valid <= '0';  -- Durante el retardo no hay datos válidos
            END IF;
        END IF;
    END PROCESS;
END BEHAVIORAL;