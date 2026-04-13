`timescale 1ns / 1ps

module fp32_int32_convert (
    input logic clk_i,
    input logic rst_i,
    input logic is_fp32_i,
    input logic [31:0] a_i,

    output logic [31:0] result_o,
    output logic nv_o
);

  logic [31:0] result_next;
  logic nv_next;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      result_o <= 32'b0;
      nv_o <= 1'b0;
    end else begin
      result_o <= result_next;
      nv_o <= nv_next;
    end
  end

  logic sign;
  logic [7:0] exp;
  logic [22:0] frac;

  assign sign = a_i[31];
  assign exp  = a_i[30:23];
  assign frac = a_i[22:0];

  // FP32 -> INT32

  logic signed [9:0] f2i_exp_val;
  logic [31:0] f2i_mantissa;
  logic [31:0] f2i_shifted_mantissa;
  logic [31:0] f2i_result;
  logic f2i_nv;

  assign f2i_exp_val  = signed'({2'b0, exp}) - 10'sd127;
  assign f2i_mantissa = {8'b0, 1'b1, frac};

  always_comb begin
    if (f2i_exp_val >= 23) begin
      f2i_shifted_mantissa = f2i_mantissa << (f2i_exp_val - 23);
    end else if (f2i_exp_val >= 0) begin
      f2i_shifted_mantissa = f2i_mantissa >> (23 - f2i_exp_val);
    end else begin
      f2i_shifted_mantissa = 32'b0;
    end
  end

  always_comb begin
    f2i_result = 32'b0;
    f2i_nv = 1'b0;

    if (exp == 8'hFF) begin
      // NaN, Infty
      f2i_nv = 1'b1;
      f2i_result = sign ? 32'h80000000 : 32'h7FFFFFFF;
    end else if (f2i_exp_val < 0) begin
      // < 1.0, subnormal
      f2i_nv = 1'b0;
      f2i_result = 32'b0;
    end else if (f2i_exp_val > 30) begin
      // INT32 overflow
      if (f2i_exp_val == 31 && sign == 1'b1 && frac == 23'b0) begin
        // -2^31
        f2i_nv = 1'b0;
        f2i_result = 32'h80000000;
      end else begin
        f2i_nv = 1'b1;
        f2i_result = sign ? 32'h80000000 : 32'h7FFFFFFF;
      end
    end else begin
      f2i_nv = 1'b0;
      f2i_result = sign ? (~f2i_shifted_mantissa + 1'b1) : f2i_shifted_mantissa;
    end
  end

  // INT32 -> FP32

  logic [31:0] int_mag;
  logic [ 5:0] leading_zeros;
  logic [31:0] shifted_int;
  logic [ 7:0] i2f_exp;
  logic [22:0] i2f_frac;
  logic [31:0] i2f_result;

  assign int_mag = sign ? (~a_i + 1'b1) : a_i;

  always_comb begin
    leading_zeros = 6'd32;
    for (int i = 0; i < 32; i++) begin
      if (int_mag[i]) begin
        leading_zeros = 6'(31 - i);
      end
    end
  end

  assign shifted_int = int_mag << leading_zeros;

  assign i2f_exp = 8'd127 + 8'(31 - leading_zeros);
  assign i2f_frac = shifted_int[30:8];

  always_comb begin
    if (leading_zeros == 6'd32) begin
      i2f_result = 32'b0;
    end else begin
      i2f_result = {sign, i2f_exp, i2f_frac};
    end
  end

  assign result_next = is_fp32_i ? f2i_result : i2f_result;
  assign nv_next = is_fp32_i ? f2i_nv : 1'b0;
endmodule

