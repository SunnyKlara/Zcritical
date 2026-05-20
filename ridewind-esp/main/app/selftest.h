#pragma once

#include <stdbool.h>

/**
 * @file selftest.h
 * @brief Production self-test mode.
 *
 * Enter by holding the encoder button during power-on.
 * Tests all hardware peripherals and displays PASS/FAIL on LCD.
 * This function never returns — device must be power-cycled after test.
 */

/**
 * Check if selftest mode should be entered.
 * Call BEFORE any driver init (reads raw GPIO).
 * @return true if encoder button is pressed at boot.
 */
bool selftest_check_entry(void);

/**
 * Run the full self-test sequence.
 * Initializes all drivers internally, runs tests, shows result.
 * Never returns.
 */
void selftest_run(void);
