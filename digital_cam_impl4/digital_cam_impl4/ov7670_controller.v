// Controller for the OV7670 camera - transfers registers to the
// camera over an I2C like bus

module ov7670_controller(
    input clk,
    input resend,
    output config_finished,
    output sioc,
    inout siod,
    output reset,
    output pwdn,
    output xclk
);

    wire [15:0] command;
    wire finished;
    wire taken;
    wire send;

    // Device write ID; see datasheet of camera module
    localparam [7:0] camera_address = 8'h42;

    assign config_finished = finished;
    assign send = ~finished;
    assign reset = 1'b1; // Normal mode
    assign pwdn = 1'b0; // Power device up

    // Clock generation for camera
    reg sys_clk = 1'b0;
    always @(posedge clk) begin
        sys_clk <= ~sys_clk;
    end
    assign xclk = sys_clk;

    ov7670_registers registers_inst(
        .clk(clk),
        .advance(taken),
        .resend(resend),
        .command(command),
        .finished(finished)
    );

    i2c_sender sender_inst(
        .clk(clk),
        .taken(taken),
        .siod(siod),
        .sioc(sioc),
        .send(send),
        .id(camera_address),
        .reg_addr(command[15:8]),
        .value(command[7:0])
    );

endmodule
