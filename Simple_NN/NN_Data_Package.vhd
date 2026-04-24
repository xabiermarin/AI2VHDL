
-- Weights and parameters of neural network

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.NN_Config_Package.all;

PACKAGE NN_Data_Package is
       
    -- =====================
    -- FULLY CONNECTED 1: 1 → 16
    -- =====================
    
    CONSTANT NN_Layer_1_Activation  : Activation_T := relu;
    CONSTANT NN_Layer_1_Inputs     : NATURAL := 1;
    CONSTANT NN_Layer_1_Outputs    : NATURAL := 16;
    CONSTANT NN_Layer_1_Out_Offset : INTEGER := 6;
    CONSTANT NN_Layer_1_Offset     : INTEGER := 1;
    CONSTANT NN_Layer_1 : NN_Weights_T(0 to NN_Layer_1_Outputs-1, 0 to NN_Layer_1_Inputs) :=
    (   -- 16 rows (neurons) × 2 values (1 weight + 1 bias)
        0  => (0, 0),
        1  => (0, 0),
        2  => (0, 0),
        3  => (0, 0),
        4  => (0, 0),
        5  => (0, 0),
        6  => (0, 0),
        7  => (0, 0),
        8  => (0, 0),
        9  => (0, 0),
        10 => (0, 0),
        11 => (0, 0),
        12 => (0, 0),
        13 => (0, 0),
        14 => (0, 0),
        15 => (0, 0)

    );

    -- =====================
    -- FULLY CONNECTED 2: 16 → 8
    -- =====================
    
    CONSTANT NN_Layer_2_Activation  : Activation_T := linear;
    CONSTANT NN_Layer_2_Inputs     : NATURAL := 16;
    CONSTANT NN_Layer_2_Outputs    : NATURAL := 8;
    CONSTANT NN_Layer_2_Out_Offset : INTEGER := 6;
    CONSTANT NN_Layer_2_Offset     : INTEGER := 1;
    CONSTANT NN_Layer_2 : NN_Weights_T(0 to NN_Layer_2_Outputs-1, 0 to NN_Layer_2_Inputs) :=
    (   -- 8 rows (neurons) × 17 values (16 weights + 1 bias)
        0 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        1 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        2 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        3 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        4 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        5 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        6 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        7 => (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    );

    -- =====================
    -- OUTPUT FULLY CONNECTED: 8 → 1
    -- =====================
    
    CONSTANT NN_Layer_3_Activation  : Activation_T := relu;
    CONSTANT NN_Layer_3_Inputs     : NATURAL := 8;
    CONSTANT NN_Layer_3_Outputs    : NATURAL := 1;
    CONSTANT NN_Layer_3_Out_Offset : INTEGER := 6;
    CONSTANT NN_Layer_3_Offset     : INTEGER := 1;
    CONSTANT NN_Layer_3 : NN_Weights_T(0 to NN_Layer_3_Outputs-1, 0 to NN_Layer_3_Inputs) :=
    (   -- 1 row (neuron) × 9 values (8 weights + 1 bias)
      0 => (0, 0, 0, 0, 0, 0, 0, 0, 0)
    );
    
END PACKAGE NN_Data_Package;