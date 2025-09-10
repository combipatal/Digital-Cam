`timescale 1ns / 1ps
`default_nettype none

module async_fifo
    #(  parameter DW  = 4,
        parameter AW  = 4 ) 
    (   // Write Interface
        input wire              w_clk,
        input wire              w_rstn,
        input wire              w_en,
        input wire [DW-1:0]     i_dat,
        output reg              w_almost_full,
        output reg              w_full,
        
        // Read Interface
        input wire              r_clk, 
        input wire              r_rstn,
        input wire              r_en,
        output wire [DW-1:0]    o_dat,
        output reg              r_almost_empty, 
        output reg              r_empty
    );
    
    // Generate-loop variables declared at module level
    genvar j, k;

    // Almost full parameter, 4 less than full capacity
    localparam AF = (1 << AW) - 4;
 
    // FIFO Memory Style: Synchronous Dual-Port RAM
    reg [DW-1:0] mem [0:((1<<AW)-1)]; 
    
    //=======================================================
    //
    //                 Write-Domain Logic
    //
    //=======================================================
    wire [AW - 1 : 0] waddr;
    wire [AW     : 0] wgraynext;        
    wire [AW     : 0] wbinnext;
    wire              wfull_val;
    wire              walmost_full_val;
    
    reg [AW: 0] wbin;
    reg [AW: 0] wptr;
    reg [AW: 0] wq1_rptr;
    reg [AW: 0] wq2_rptr;
    
    always @(posedge w_clk) begin
        if (w_en && !w_full) begin
            mem[waddr] <= i_dat; 
        end
    end
            
    always @(posedge w_clk or negedge w_rstn) begin
        if (!w_rstn) begin
            {wq2_rptr, wq1_rptr} <= 0;
        end
        else begin
            {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr}; 
        end
    end  
    
    always @(posedge w_clk or negedge w_rstn) begin
        if (!w_rstn) begin
            {wbin, wptr} <= 0;
        end
        else begin
            {wbin, wptr} <= {wbinnext, wgraynext}; 
        end
    end
            
    assign waddr     = wbin[AW-1:0];
    assign wbinnext  = wbin + { {(AW){1'b0}}, (w_en && !w_full) };
    assign wgraynext = (wbinnext >> 1) ^ wbinnext; 
    
    assign wfull_val = (wgraynext == {~wq2_rptr[AW:AW-1], wq2_rptr[AW-2:0]});  
                                      
    always @(posedge w_clk or negedge w_rstn) begin
        if (!w_rstn) begin
            w_full <= 1'b0;
        end
        else begin
            w_full <= wfull_val; 
        end
    end 
    
    wire [AW :0] wq2_rptr_bin;  
    wire [AW :0] wbin_rbin_diff;

    assign wq2_rptr_bin[AW] = wq2_rptr[AW]; 
    generate
        // genvar j; // Moved to module scope
        for (j = AW - 1; j >= 0; j = j - 1) begin : g2b_w
            assign wq2_rptr_bin[j] = wq2_rptr_bin[j+1] ^ wq2_rptr[j]; 
        end 
    endgenerate 
    
    assign wbin_rbin_diff  = (wbinnext > wq2_rptr_bin) ? (wbinnext - wq2_rptr_bin) 
                                                       : (wbinnext - wq2_rptr_bin + (1 << (AW+1))); 

    assign walmost_full_val = (wbin_rbin_diff >=  AF);
                                                
    always @(posedge w_clk or negedge w_rstn) begin
        if (!w_rstn) begin
            w_almost_full <= 1'b0; 
        end
        else begin
            w_almost_full <= walmost_full_val;
        end
    end                       
        
    /** =======================================================
        
                        Read-Domain Logic
    
        ======================================================= **/ 
    wire [AW - 1 :0] raddr;
    wire [AW     :0] rgraynext;
    wire [AW     :0] rbinnext; 
    wire              rempty_val;
    wire              ralmost_empty_val;

    reg [AW       :0] rbin;
    reg [AW       :0] rptr;
    reg [AW       :0] rq1_wptr;
    reg [AW       :0] rq2_wptr;
    
    assign o_dat = mem[raddr]; 

    always @(posedge r_clk or negedge r_rstn) begin
        if (!r_rstn) begin
            {rq2_wptr, rq1_wptr} <= 0;
        end
        else begin
            {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr}; 
        end
    end 
    
    always @(posedge r_clk or negedge r_rstn) begin
        if (!r_rstn) begin
            {rbin, rptr} <= 0;
        end
        else begin
            {rbin, rptr} <= {rbinnext, rgraynext}; 
        end
    end 
    
    assign raddr     =  rbin[AW-1:0];  
    assign rbinnext  =  rbin + { {(AW){1'b0}}, (r_en && !r_empty) };
    assign rgraynext = (rbinnext >> 1) ^ rbinnext; 
    
    assign rempty_val = (rgraynext == rq2_wptr); 

    always @(posedge r_clk or negedge r_rstn) begin
        if (!r_rstn) begin
            r_empty <= 1'b1;
        end
        else begin
            r_empty <= rempty_val; 
        end
    end 
    
    wire [AW :0] rq2_wptr_bin;  
    wire [AW :0] rbin_wbin_diff;
    
    assign rq2_wptr_bin[AW] = rq2_wptr[AW]; 
    generate
        // genvar k; // Moved to module scope
        for (k = AW - 1; k >= 0; k = k - 1) begin : g2b_r
            assign rq2_wptr_bin[k] = rq2_wptr_bin[k+1] ^ rq2_wptr[k];
        end
    endgenerate
    
    assign rbin_wbin_diff    = (rbinnext > rq2_wptr_bin) ? (rq2_wptr_bin - rbinnext + (1 << (AW+1)))
                                                        : (rq2_wptr_bin - rbinnext);
    assign ralmost_empty_val  = (rbin_wbin_diff <= 4);

    always @(posedge r_clk or negedge r_rstn) begin
        if (!r_rstn) begin
            r_almost_empty <= 1'b1;
        end
        else begin
            r_almost_empty <= ralmost_empty_val;
        end
    end
        
endmodule