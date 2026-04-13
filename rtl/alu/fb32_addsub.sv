`timescale 1ns / 1ps

module fp32_addsub (
    input logic        clk_i,
    input logic        rst_i,
    input logic        is_add_i,
    input logic [31:0] a_i,
    input logic [31:0] b_i,

    output logic [31:0] result_o,
    output logic        nv_o
);

  logic [31:0] result_next;
  logic        nv_next;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      result_o <= 32'b0;
      nv_o     <= 1'b0;
    end else begin
      result_o <= result_next;
      nv_o     <= nv_next;
    end
  end

  logic a_sign, b_sign;
  logic [7:0] a_exp, b_exp;
  logic [22:0] a_frac, b_frac;

  assign a_sign = a_i[31];
  assign a_exp  = a_i[30:23];
  assign a_frac = a_i[22:0];

  assign b_sign = b_i[31];
  assign b_exp  = b_i[30:23];
  assign b_frac = b_i[22:0];

  logic b_eff_sign;
  assign b_eff_sign = is_add_i ? b_sign : ~b_sign;

  logic a_is_sub, b_is_sub;
  logic a_is_zero, b_is_zero;
  logic a_is_inf, b_is_inf;
  logic a_is_nan, b_is_nan;

  assign a_is_sub  = (a_exp == 8'd0 && a_frac != 23'd0);
  assign b_is_sub  = (b_exp == 8'd0 && b_frac != 23'd0);
  assign a_is_zero = (a_exp == 8'd0 && a_frac == 23'd0);
  assign b_is_zero = (b_exp == 8'd0 && b_frac == 23'd0);
  assign a_is_inf  = (a_exp == 8'hff && a_frac == 23'd0);
  assign b_is_inf  = (b_exp == 8'hff && b_frac == 23'd0);
  assign a_is_nan  = (a_exp == 8'hff && a_frac != 23'd0);
  assign b_is_nan  = (b_exp == 8'hff && b_frac != 23'd0);

  logic [8:0] a_true_exp;
  logic [8:0] b_true_exp;

  assign a_true_exp = a_is_sub ? 9'd1 : {1'b0, a_exp};
  assign b_true_exp = b_is_sub ? 9'd1 : {1'b0, b_exp};

  logic [23:0] a_sig;
  logic [23:0] b_sig;

  assign a_sig = a_is_zero ? 24'd0 : (a_is_sub ? {1'b0, a_frac} : {1'b1, a_frac});
  assign b_sig = b_is_zero ? 24'd0 : (b_is_sub ? {1'b0, b_frac} : {1'b1, b_frac});

  logic a_larger;
  always_comb begin
    if (a_true_exp > b_true_exp) begin
      a_larger = 1'b1;
    end else if (a_true_exp < b_true_exp) begin
      a_larger = 1'b0;
    end else begin
      a_larger = (a_sig >= b_sig);
    end
  end

  logic [8:0] l_exp, s_exp;
  logic [23:0] l_sig, s_sig;
  logic l_sign, s_sign;

  always_comb begin
    if (a_larger) begin
      l_exp  = a_true_exp;
      l_sig  = a_sig;
      l_sign = a_sign;
      s_exp  = b_true_exp;
      s_sig  = b_sig;
      s_sign = b_eff_sign;
    end else begin
      l_exp  = b_true_exp;
      l_sig  = b_sig;
      l_sign = b_eff_sign;
      s_exp  = a_true_exp;
      s_sig  = a_sig;
      s_sign = a_sign;
    end
  end

  logic [ 8:0] exp_diff;
  logic [48:0] l_val;
  logic [48:0] s_val;
  logic        sticky;

  assign exp_diff = l_exp - s_exp;
  assign l_val    = {1'b0, l_sig, 24'b0};

  always_comb begin
    if (exp_diff > 9'd24) begin
      s_val  = 49'b0;
      sticky = (s_sig != 24'b0);
    end else begin
      s_val  = {1'b0, s_sig, 24'b0} >> exp_diff;
      sticky = 1'b0;
    end
  end

  logic        is_sub;
  logic [48:0] sum_val;

  assign is_sub = (l_sign != s_sign);

  always_comb begin
    if (is_sub) begin
      sum_val = l_val - s_val - {48'b0, sticky};
    end else begin
      sum_val = l_val + s_val + {48'b0, sticky};
    end
  end

  // normalization
  logic [5:0] lz;

  always_comb begin
    lz = 6'd49;
    for (int i = 0; i <= 48; i++) begin
      if (sum_val[i]) begin
        lz = 6'(48 - i);
      end
    end
  end

  logic [ 8:0] max_shift;
  logic [ 8:0] actual_shift;
  logic [ 8:0] norm_exp;
  logic [48:0] sum_val_shifted;
  logic [23:0] norm_sig;

  assign max_shift = l_exp;
  assign actual_shift = ({3'b0, lz} <= max_shift) ? {3'b0, lz} : max_shift;

  assign norm_exp = l_exp + 9'd1 - actual_shift;

  assign sum_val_shifted = sum_val << actual_shift;
  assign norm_sig = sum_val_shifted[48:25];

  logic [31:0] normal_result;

  logic [22:0] trunc_norm_sig;
  logic [ 7:0] trunc_norm_exp;
  logic        norm_sig_23;

  assign trunc_norm_sig = norm_sig[22:0];
  assign trunc_norm_exp = norm_exp[7:0];
  assign norm_sig_23    = norm_sig[23];

  always_comb begin
    if (sum_val == 49'b0) begin
      normal_result = 32'b0;
    end else if (norm_exp >= 9'd255) begin
      // overflow
      normal_result = {l_sign, 8'hfe, 23'h7fffff};
    end else if (norm_sig_23 == 1'b0) begin
      // subnormal
      normal_result = {l_sign, 8'h00, trunc_norm_sig};
    end else begin
      normal_result = {l_sign, trunc_norm_exp, trunc_norm_sig};
    end
  end

  // nan, inf, zeroes
  always_comb begin
    result_next = normal_result;
    nv_next     = 1'b0;

    if (a_is_nan || b_is_nan) begin
      result_next = 32'h7fc00000;
    end else if (a_is_inf && b_is_inf) begin
      if (a_sign != b_eff_sign) begin
        result_next = 32'h7fc00000;  // inf + (-inf) -> qnan
        nv_next     = 1'b1;
      end else begin
        result_next = {a_sign, 8'hff, 23'd0};  // inf + inf -> inf
      end
    end else if (a_is_inf) begin
      result_next = {a_sign, 8'hff, 23'd0};
    end else if (b_is_inf) begin
      result_next = {b_eff_sign, 8'hff, 23'd0};
    end else if (a_is_zero && b_is_zero) begin
      result_next = {(a_sign & b_eff_sign), 31'b0};
    end else if (sum_val == 49'b0) begin
      result_next = 32'b0;
    end
  end

endmodule
