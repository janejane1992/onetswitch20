///////////////////////////////////////////////////////////////////////////////
// Module: queue_splitter.v
// Description: dispatch incoming packets to different packet queues.
//
///////////////////////////////////////////////////////////////////////////////

module queue_splitter #(
   parameter DATA_WIDTH = 64,
   parameter CTRL_WIDTH=DATA_WIDTH/8,
   parameter UDP_REG_SRC_WIDTH = 2,
   parameter NUM_QUEUES = 4,
   parameter MAX_NUM_QUEUES = 8
)(// --- data path interface
    output     [DATA_WIDTH-1:0]        out_data_0,
    output     [CTRL_WIDTH-1:0]        out_ctrl_0,
    input                              out_rdy_0,
    output reg                         out_wr_0,

    output     [DATA_WIDTH-1:0]        out_data_1,
    output     [CTRL_WIDTH-1:0]        out_ctrl_1,
    input                              out_rdy_1,
    output reg                         out_wr_1,

    output     [DATA_WIDTH-1:0]        out_data_2,
    output     [CTRL_WIDTH-1:0]        out_ctrl_2,
    input                              out_rdy_2,
    output reg                         out_wr_2,

    output     [DATA_WIDTH-1:0]        out_data_3,
    output     [CTRL_WIDTH-1:0]        out_ctrl_3,
    input                              out_rdy_3,
    output reg                         out_wr_3,

    output     [DATA_WIDTH-1:0]        out_data_4,
    output     [CTRL_WIDTH-1:0]        out_ctrl_4,
    input                              out_rdy_4,
    output reg                         out_wr_4,

    output  [DATA_WIDTH-1:0]           out_data_5,
    output  [CTRL_WIDTH-1:0]           out_ctrl_5,
    output reg                         out_wr_5,
    input                              out_rdy_5,

    output  [DATA_WIDTH-1:0]           out_data_6,
    output  [CTRL_WIDTH-1:0]           out_ctrl_6,
    output reg                         out_wr_6,
    input                              out_rdy_6,

    output  [DATA_WIDTH-1:0]           out_data_7,
    output  [CTRL_WIDTH-1:0]           out_ctrl_7,
    output reg                         out_wr_7,
    input                              out_rdy_7,

    // --- Interface to the previous module
    input  [DATA_WIDTH-1:0]            in_data,
    input  [CTRL_WIDTH-1:0]            in_ctrl,
    output                             in_rdy,
    input                              in_wr,

    // --- Register interface
    input                              reg_req_in,
    input                              reg_ack_in,
    input                              reg_rd_wr_L_in,
    input  [`UDP_REG_ADDR_WIDTH-1:0]   reg_addr_in,
    input  [`CPCI_NF2_DATA_WIDTH-1:0]  reg_data_in,
    input  [UDP_REG_SRC_WIDTH-1:0]     reg_src_in,

    output reg                            reg_req_out,
    output reg                            reg_ack_out,
    output reg                            reg_rd_wr_L_out,
    output reg [`UDP_REG_ADDR_WIDTH-1:0]  reg_addr_out,
    output reg [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
    output reg [UDP_REG_SRC_WIDTH-1:0]    reg_src_out,

    // --- Misc
    input                              clk,
    input                              reset);

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   //------------- Internal Parameters ---------------
   parameter NUM_OQ_WIDTH       = log2(NUM_QUEUES);
   parameter PKT_LEN_WIDTH      = 11;
   parameter PKT_WORDS_WIDTH    = PKT_LEN_WIDTH-log2(CTRL_WIDTH);
   parameter MAX_PKT            = 2048;   // allow for 2K bytes
   parameter PKT_BYTE_CNT_WIDTH = log2(MAX_PKT);
   parameter PKT_WORD_CNT_WIDTH = log2(MAX_PKT/CTRL_WIDTH);

   //--------------- Regs/Wires ----------------------


   wire                       input_fifo_rd_en;
   wire                       input_fifo_empty;
   wire [DATA_WIDTH-1:0]      input_fifo_data_out;
   wire [CTRL_WIDTH-1:0]      input_fifo_ctrl_out;
   reg [DATA_WIDTH-1:0]       input_fifo_data_out_d;
   reg [CTRL_WIDTH-1:0]       input_fifo_ctrl_out_d;
   wire                       input_fifo_nearly_full;
   wire [DATA_WIDTH+CTRL_WIDTH-1:0] output_fifo_dout[MAX_NUM_QUEUES-1 : 0];
   reg                        input_fifo_out_vld;
   
   reg [MAX_NUM_QUEUES-1:0]  output_fifo_wr_en;
   wire [MAX_NUM_QUEUES-1:0] output_fifo_rd_en;
   wire [MAX_NUM_QUEUES-1:0] output_fifo_empty;
   wire [MAX_NUM_QUEUES-1:0] output_fifo_almost_full;
   
   wire [MAX_NUM_QUEUES-1:0] output_fifo_wr_en_calc;
   reg [MAX_NUM_QUEUES-1:0] output_fifo_wr_en_reg;
   //---------------- Modules ------------------------

   
   small_fifo #(.WIDTH(DATA_WIDTH+CTRL_WIDTH),.MAX_DEPTH_BITS(3))
      input_fifo
        (.din({in_ctrl, in_data}),  // Data in
         .wr_en         (in_wr),             // Write enable
         .rd_en         (input_fifo_rd_en),    // Read the next word
         .dout({input_fifo_ctrl_out, input_fifo_data_out}),
         .full          (),
         .prog_full     (),
         .nearly_full   (input_fifo_nearly_full),
         .empty         (input_fifo_empty),
         .reset         (reset),
         .clk           (clk)
         );
   generate genvar i;
      for(i=0; i<NUM_QUEUES; i=i+1) begin: output_fifos
         pkt_fifo output_fifo
         (  .din ({input_fifo_ctrl_out_d, input_fifo_data_out_d}),  // Data in
            .wr_en         (output_fifo_wr_en[i]),             // Write enable
            .rd_en         (output_fifo_rd_en[i]),    // Read the next word
            .dout          (output_fifo_dout[i]),
            .full          (),
            .prog_full     (output_fifo_almost_full[i]),
            .empty         (output_fifo_empty[i]),
            //.reset         (reset),
            .rst         (reset),
            .clk           (clk)
         );
      end // block: output_fifos
   endgenerate




   //------------------ Logic ------------------------
   
   assign in_rdy = !input_fifo_nearly_full;
   assign input_fifo_rd_en = !input_fifo_empty;
   
   assign output_fifo_rd_en[0] = !output_fifo_empty[0] && out_rdy_0;
   assign output_fifo_rd_en[1] = !output_fifo_empty[1] && out_rdy_1;
   assign output_fifo_rd_en[2] = !output_fifo_empty[2] && out_rdy_2;
   assign output_fifo_rd_en[3] = !output_fifo_empty[3] && out_rdy_3;
   assign output_fifo_rd_en[4] = !output_fifo_empty[4] && out_rdy_4;
   assign output_fifo_rd_en[5] = !output_fifo_empty[5] && out_rdy_5;
   assign output_fifo_rd_en[6] = !output_fifo_empty[6] && out_rdy_6;
   assign output_fifo_rd_en[7] = !output_fifo_empty[7] && out_rdy_7;
   
   assign {out_ctrl_0,out_data_0} = output_fifo_dout[0];
   assign {out_ctrl_1,out_data_1} = output_fifo_dout[1];
   assign {out_ctrl_2,out_data_2} = output_fifo_dout[2];
   assign {out_ctrl_3,out_data_3} = output_fifo_dout[3];
   assign {out_ctrl_4,out_data_4} = output_fifo_dout[4];
   assign {out_ctrl_5,out_data_5} = output_fifo_dout[5];
   assign {out_ctrl_6,out_data_6} = output_fifo_dout[6];
   assign {out_ctrl_7,out_data_7} = output_fifo_dout[7];

   
   always @(posedge clk) begin
      if(reset) begin
         out_wr_0 <= 0;
         out_wr_1 <= 0;
         out_wr_2 <= 0;
         out_wr_3 <= 0;
         out_wr_4 <= 0;
         out_wr_5 <= 0;
         out_wr_6 <= 0;
         out_wr_7 <= 0;
      end
      else begin
         out_wr_0 <= output_fifo_rd_en[0];
         out_wr_1 <= output_fifo_rd_en[1];
         out_wr_2 <= output_fifo_rd_en[2];
         out_wr_3 <= output_fifo_rd_en[3];
         out_wr_4 <= output_fifo_rd_en[4];
         out_wr_5 <= output_fifo_rd_en[5];
         out_wr_6 <= output_fifo_rd_en[6];
         out_wr_7 <= output_fifo_rd_en[7];
      end
   end // always @ (posedge clk)
   
   reg [7:0] output_state;
   localparam  PKT_START = 8'h1,
               PKT_HDR   = 8'h2,
               WRITE_PKT = 8'h4;
   always @(posedge clk)begin
      if(reset) begin 
         input_fifo_out_vld <= 0;
         output_fifo_wr_en <= 0;
         output_fifo_wr_en_reg <= 0;
         input_fifo_data_out_d <= 64'b0;
         input_fifo_ctrl_out_d <= 8'b0;
         output_state <= PKT_START;
      end
      else begin
         //stage 1
         input_fifo_data_out_d <= input_fifo_data_out;
         input_fifo_ctrl_out_d <= input_fifo_ctrl_out;

         input_fifo_out_vld <= input_fifo_rd_en;
         output_fifo_wr_en <= 0;
         //stage 2
         case(output_state)
            PKT_START: begin
               if(input_fifo_out_vld && input_fifo_ctrl_out==`IO_QUEUE_STAGE_NUM) begin
                  output_fifo_wr_en <= output_fifo_wr_en_calc;
                  output_fifo_wr_en_reg <= output_fifo_wr_en_calc;
                  output_state <= PKT_HDR;
               end
            end
            PKT_HDR: begin
               if(input_fifo_out_vld) begin
                  output_fifo_wr_en <= output_fifo_wr_en_reg;
                  if(input_fifo_ctrl_out ==0) output_state <= WRITE_PKT;
               end
            end
            WRITE_PKT: begin
               if(input_fifo_out_vld) begin
                  output_fifo_wr_en <= output_fifo_wr_en_reg;
                  if(input_fifo_ctrl_out !=0) begin 
                     output_state <= PKT_START;
                     output_fifo_wr_en_reg <= 0;
                  end
               end
            end 
         endcase         
      end
   end
   
   //if the target queue is almost full, wr_en will not be valid, then the packet is dropped
   assign output_fifo_wr_en_calc = ~output_fifo_almost_full & input_fifo_data_out[`IOQ_DST_PORT_POS + 8 + MAX_NUM_QUEUES - 1:`IOQ_DST_PORT_POS + 8];
   // registers unused 
   always @(posedge clk) begin
      reg_req_out        <= reg_req_in;
      reg_ack_out        <= reg_ack_in;
      reg_rd_wr_L_out    <= reg_rd_wr_L_in;
      reg_addr_out       <= reg_addr_in;
      reg_data_out       <= reg_data_in;
      reg_src_out        <= reg_src_in;
   end
endmodule // queue_splitter




