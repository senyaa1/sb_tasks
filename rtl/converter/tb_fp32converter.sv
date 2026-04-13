`timescale 1ns / 1ps

module tb_fp32_int32_convert;
  logic clk_i;
  logic rst_i;
  logic is_fp32_i;
  logic [31:0] a_i;

  logic [31:0] result_o;
  logic nv_o;

  fp32_int32_convert dut (
      .clk_i(clk_i),
      .rst_i(rst_i),
      .is_fp32_i(is_fp32_i),
      .a_i(a_i),
      .result_o(result_o),
      .nv_o(nv_o)
  );

  always #5 clk_i = ~clk_i;

  task test_vector(input logic t_is_fp32, input logic [31:0] t_a_i, input logic [31:0] t_exp_result,
                   input logic t_exp_nv, input string description);
    begin
      @(negedge clk_i);
      is_fp32_i = t_is_fp32;
      a_i = t_a_i;

      @(negedge clk_i);

      if (result_o !== t_exp_result || nv_o !== t_exp_nv) begin
        $error(
            "FAIL: %s\n Input: is_fp32=%b, a_i=0x%h\n Expected: result=0x%h, nv=%b\n Got : result=0x%h, nv=%b",
            description, t_is_fp32, t_a_i, t_exp_result, t_exp_nv, result_o, nv_o);
      end else begin
        $display("PASS: %s | in=0x%h -> out=0x%h, nv=%b", description, t_a_i, result_o, nv_o);
      end
    end
  endtask

  initial begin
    clk_i = 0;
    rst_i = 1;
    is_fp32_i = 0;
    a_i = 32'b0;

    #15;
    rst_i = 0;
    @(negedge clk_i);

    $display("Starting simulation");

    test_vector(1'b1, 32'hc608ec00, 32'hFFFFDDC5, 1'b0, "FP32 -> INT32 (-8763.0)");

    test_vector(1'b0, 32'h0034D57A, 32'h4a5355e8, 1'b0, "INT32 -> FP32 (3462522)");
    test_vector(1'b1, 32'h5a5005e8, 32'h7FFFFFFF, 1'b1, "FP32 -> INT32 (positive overflow)");
    test_vector(1'b1, 32'hda5005e8, 32'h80000000, 1'b1, "FP32 -> INT32 (negative overflow)");
    test_vector(1'b1, 32'h80000000, 32'h00000000, 1'b0, "FP32 -> INT32 (-0.0)");
    test_vector(1'b1, 32'h7FC00000, 32'h7FFFFFFF, 1'b1, "FP32 -> INT32 (+qNaN)");
    test_vector(1'b1, 32'h7F800000, 32'h7FFFFFFF, 1'b1, "FP32 -> INT32 (+Inf)");
    test_vector(1'b1, 32'hFF800000, 32'h80000000, 1'b1, "FP32 -> INT32 (-Inf)");
    test_vector(1'b0, 32'h00000000, 32'h00000000, 1'b0, "INT32 -> FP32 (0 -> 0.0)");
    test_vector(1'b0, 32'hFFFFFFFF, 32'hBF800000, 1'b0, "INT32 -> FP32 (-1 -> -1.0)");
    test_vector(1'b1, 32'h407F5C29, 32'h00000003, 1'b0, "FP32 -> INT32 (3.99 -> 3)");

    $finish;
  end

endmodule

