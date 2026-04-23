
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.CNN_Config_Package.all;
use work.CNN_Data_Package.all;

ENTITY Simple_NN IS
    PORT (
        CLK : IN STD_LOGIC;
        iStream     : IN CNN_Stream_T;
        iData       : IN CNN_Values_T(0 downto 0);

        Result      : OUT CNN_Value_T;
        Update      : OUT STD_LOGIC
    );
END Simple_NN;

ARCHITECTURE BEHAVIORAL OF Simple_NN IS

    -- Signals between layer 1 and layer 2
    SIGNAL oStream_1N : CNN_Stream_T;
    SIGNAL oData_1N   : CNN_Values_T(NN_Layer_1_Outputs-1 downto 0);

    -- Signals between layer 2 and layer 3
    SIGNAL oStream_2N : CNN_Stream_T;
    SIGNAL oData_2N   : CNN_Values_T(NN_Layer_2_Outputs-1 downto 0);

    -- Output signals of layer 3
    SIGNAL oStream_3N : CNN_Stream_T;
    SIGNAL oData_3N   : CNN_Values_T(NN_Layer_3_Outputs-1 downto 0);

    COMPONENT NN_Layer IS
        GENERIC (
            Inputs          : NATURAL := 16;
            Outputs         : NATURAL := 8;
            Activation      : Activation_T := relu;
            Input_Cycles    : NATURAL := 1;
            Calc_Cycles     : NATURAL := 1;
            Output_Cycles   : NATURAL := 1;
            Output_Delay    : NATURAL := 1;
            Offset_In       : INTEGER := 0;
            Offset_Out      : INTEGER := 0;
            Offset          : INTEGER := 0;
            Weights         : CNN_Weights_T
            
        );
        PORT (
            iStream : IN  CNN_Stream_T;
            iData   : IN  CNN_Values_T(Inputs/Input_Cycles-1 downto 0);
            iCycle  : IN  NATURAL range 0 to Input_Cycles-1;
            
            oStream : OUT CNN_Stream_T;
            oData   : OUT CNN_Values_T(Outputs/Output_Cycles-1 downto 0) := (others => 0);
            oCycle  : OUT NATURAL range 0 to Output_Cycles-1
            
        );
    END COMPONENT;
    
BEGIN    
    NN_Layer1 : NN_Layer  -- First Fully Connected Layer
    GENERIC MAP (
        Inputs          => NN_Layer_1_Inputs,
        Outputs         => NN_Layer_1_Outputs,
        Activation      => NN_Layer_1_Activation,
        Input_Cycles    => 1,
        Calc_Cycles     => 1,
        Output_Cycles   => 1,
        Offset_In       => 0,
        Offset_Out      => NN_Layer_1_Out_Offset,
        Offset          => NN_Layer_1_Offset,
        Weights         => NN_Layer_1
    ) 
    PORT MAP (
        iStream         => iStream,
        iData           => iData,
        iCycle          => 0,
        oStream         => oStream_1N,
        oData           => oData_1N,
        oCycle          => open
    );

    NN_Layer2 : NN_Layer  -- Second Fully Connected Layer
    GENERIC MAP (
        Inputs          => NN_Layer_2_Inputs,
        Outputs         => NN_Layer_2_Outputs,
        Activation      => NN_Layer_2_Activation,
        Input_Cycles    => 1,
        Calc_Cycles     => 1,
        Output_Cycles   => 1,
        Offset_In       => NN_Layer_1_Out_Offset,
        Offset_Out      => NN_Layer_2_Out_Offset,
        Offset          => NN_Layer_2_Offset,
        Weights         => NN_Layer_2
    ) 
    PORT MAP (
        iStream         => oStream_1N,
        iData           => oData_1N,
        iCycle          => 0,
        oStream         => oStream_2N,
        oData           => oData_2N,
        oCycle          => open
    );

    NN_Layer3 : NN_Layer  -- Output Fully Connected Layer
    GENERIC MAP (
        Inputs          => NN_Layer_3_Inputs,
        Outputs         => NN_Layer_3_Outputs,
        Activation      => NN_Layer_3_Activation,
        Input_Cycles    => 1,
        Calc_Cycles     => 1,
        Output_Cycles   => 1,
        Offset_In       => NN_Layer_2_Out_Offset,
        Offset_Out      => NN_Layer_3_Out_Offset,
        Offset          => NN_Layer_3_Offset,
        Weights         => NN_Layer_3
    ) 
    PORT MAP (
        iStream         => oStream_2N,
        iData           => oData_2N,
        iCycle          => 0,
        oStream         => oStream_3N,
        oData           => oData_3N,
        oCycle          => open
    );

    PROCESS (oStream_3N)
    BEGIN
        IF (rising_edge(oStream_3N.Data_CLK)) THEN
            IF (oStream_3N.Data_Valid = '1') THEN
                Result <= oData_3N(0);
                Update <= '1';
            ELSE
                Update <= '0';
            END IF;
        END IF;
    END PROCESS;
END BEHAVIORAL;