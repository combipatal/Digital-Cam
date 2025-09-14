// Create a buffer to store pixels data for a frame of 320x240 pixels;
// Data for each pixel is 12 bits;
// That is 76800 pixels; hence, address is represented on 17 bits
// (2^17 = 131072 > 76800);
// Notes:
// 1) If we wanted to work with 640x480 pixels, that would require
// an amount of embedded RAM that is not available on the Cyclone IV E of DE2-115;
// 2) We create the buffer with 76800 by stacking-up two blocks
// of 2^16 = 65536 addresses;

module frame_buffer(
    input [11:0] data,
    input [16:0] rdaddress,
    input rdclock,
    input [16:0] wraddress,
    input wrclock,
    input wren,
    output [11:0] q
);

    // Read signals
    wire [11:0] q_top, q_bottom;

    // Write signals
    wire wren_top, wren_bottom;

    my_frame_buffer_15to0 buffer_top(
        .data(data[11:0]),
        .rdaddress(rdaddress[15:0]),
        .rdclock(rdclock),
        .wraddress(wraddress[15:0]),
        .wrclock(wrclock),
        .wren(wren_top),
        .q(q_top)
    );

    my_frame_buffer_15to0 buffer_bottom(
        .data(data[11:0]),
        .rdaddress(rdaddress[15:0]),
        .rdclock(rdclock),
        .wraddress(wraddress[15:0]),
        .wrclock(wrclock),
        .wren(wren_bottom),
        .q(q_bottom)
    );

    // Write enable logic
    assign wren_top = (wraddress[16] == 1'b0) ? wren : 1'b0;
    assign wren_bottom = (wraddress[16] == 1'b1) ? wren : 1'b0;

    // Read data multiplexing
    assign q = (rdaddress[16] == 1'b0) ? q_top :
               (rdaddress[16] == 1'b1) ? q_bottom : 12'b0;

endmodule
