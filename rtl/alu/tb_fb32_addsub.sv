`timescale 1ns / 1ps

module tb_fb32_addsub;
  logic        clk_i;
  logic        rst_i;
  logic        is_add_i;
  logic [31:0] a_i;
  logic [31:0] b_i;

  logic [31:0] result_o;
  logic        nv_o;

  fp32_addsub dut (
      .clk_i(clk_i),
      .rst_i(rst_i),
      .is_add_i(is_add_i),
      .a_i(a_i),
      .b_i(b_i),
      .result_o(result_o),
      .nv_o(nv_o)
  );

  always #5 clk_i = ~clk_i;

  task test_vector(input logic t_is_add, input logic [31:0] t_a, input logic [31:0] t_b,
                   input logic [31:0] t_exp_result, input logic t_exp_nv, input string description);
    begin
      @(negedge clk_i);
      is_add_i = t_is_add;
      a_i      = t_a;
      b_i      = t_b;

      @(negedge clk_i);

      if (result_o !== t_exp_result || nv_o !== t_exp_nv) begin
        $error(
            "FAIL: %s\n  Input: is_add=%b, a=0x%h, b=0x%h\n  Expected: result=0x%h, nv=%b\n  Got : result=0x%h, nv=%b",
            description, t_is_add, t_a, t_b, t_exp_result, t_exp_nv, result_o, nv_o);
      end else begin
        $display("PASS: %s | a=0x%h, b=0x%h -> out=0x%h, nv=%b", description, t_a, t_b, result_o,
                 nv_o);
      end
    end
  endtask

  initial begin
    clk_i    = 0;
    rst_i    = 1;
    is_add_i = 0;
    a_i      = 32'b0;
    b_i      = 32'b0;

    #15;
    rst_i = 0;
    @(negedge clk_i);

    test_vector(1'b1, 32'hff7fffff, 32'hff7fffff, 32'hff7fffff, 1'b0, "overflow");
    test_vector(1'b1, 32'hd7627b5f, 32'hd5682615, 32'hd770fdc0, 1'b0, "add two negatives");
    test_vector(1'b0, 32'h7fc00000, 32'h00000000, 32'h7fc00000, 1'b0, "qnan - 0 -> qnan");
    test_vector(1'b1, 32'h7f800000, 32'hff800000, 32'h7fc00000, 1'b1,
                "+inf + (-inf) -> qnan (nv=1)");
    test_vector(1'b0, 32'h7f800000, 32'h7f800000, 32'h7fc00000, 1'b1,
                "inf - (+inf) -> qnan (nv=1)");
    test_vector(1'b1, 32'h7f800000, 32'h7f800000, 32'h7f800000, 1'b0,
                "+inf + (+inf) -> +inf (nv=0)");
    test_vector(1'b1, 32'h7f7fffff, 32'h7f7fffff, 32'h7f7fffff, 1'b0,
                "+max + +max -> +max (overflow)");
    test_vector(1'b0, 32'h3f800000, 32'h3f800000, 32'h00000000, 1'b0, "1.0 - 1.0 -> +0.0");
    test_vector(1'b1, 32'h3fc00000, 32'h40200000, 32'h40800000, 1'b0, "1.5 + 2.5 -> 4.0");
    $finish;
  end

endmodule



