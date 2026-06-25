extends GutTest
# Placeholder test — validates that the GUT test infrastructure boots correctly.
# This file must remain passing; it is the CI health-check for the pipeline.

func test_placeholder() -> void:
	assert_eq(1, 1, "placeholder")
