// Master reset
// Reset asserted when button is pressed (active-high)
// or PLL has not yet locked.

module master_reset(
    input reset_ext,    // Reset from external button
    input pll_lock,
    output reset
);

assign reset = reset_ext | ~pll_lock;

endmodule