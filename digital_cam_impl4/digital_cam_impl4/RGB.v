module RGB(
    input [11:0] Din,     // pixel gray level on 8 bits
    input Nblank,         // signal indicating display areas, outside the display area
                           // all three colors take 0
    output [7:0] R,       // three colors on 8 bits
    output [7:0] G,
    output [7:0] B
);

    // Assign RGB values based on Nblank signal
    assign R = (Nblank == 1'b1) ? {Din[11:8], Din[11:8]} : 8'b0;
    assign G = (Nblank == 1'b1) ? {Din[7:4], Din[7:4]} : 8'b0;
    assign B = (Nblank == 1'b1) ? {Din[3:0], Din[3:0]} : 8'b0;

endmodule
