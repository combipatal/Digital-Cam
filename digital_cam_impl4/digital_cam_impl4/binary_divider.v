// Binary divider implementation
// Version 1: simply convert std_logic_vector to unsigned; divide
// directly, and then, convert back to std_logic_vector;
// Note: this is the most straightforward (i.e., the lazy man's) solution;
// but we have no control of its internal structure;
// also, note that it's a combinational circuit; does not use a clk signal;

module binary_divider_ver1 #(parameter size = 8)(
    input [size-1:0] A,
    input [size-1:0] B,
    output [size-1:0] Q, // quotient
    output [size-1:0] R  // remainder
);

    // Convert inputs to integers for division
    wire signed [size-1:0] A_signed = $signed(A);
    wire signed [size-1:0] B_signed = $signed(B);

    // Perform division
    wire signed [size-1:0] Q_signed = A_signed / B_signed;
    wire signed [size-1:0] R_signed = A_signed % B_signed;

    // Convert back to unsigned for output
    assign Q = $unsigned(Q_signed);
    assign R = $unsigned(R_signed);

endmodule
