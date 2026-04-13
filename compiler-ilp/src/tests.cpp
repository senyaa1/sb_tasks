#include "solver.hpp"
#include <gtest/gtest.h>
#include <iostream>
#include <string>
#include <vector>


TEST(SoftwarePipeliningTest, ThreeNodeLoop)
{
	Graph instance{.nodes = {{0, OpType::kLoad}, {1, OpType::kCompute}, {2, OpType::kStore}},
		       .edges = {{0, 1, 4, "dd"}, {1, 2, 2, "dd"}, {1, 1, 1, "ld"}}};

	constexpr int kMaxUnrollFactor = 4;
	constexpr int kMaxIiNumerator = 10;

	ScheduleResult result = FindBestSchedule(instance, kMaxUnrollFactor, kMaxIiNumerator);

	EXPECT_TRUE(result.found);

	if (result.found)
	{
		std::cout << "[          ] Found valid schedule with II = " << result.ii_numerator << "/"
			  << result.unroll_factor << " (" << result.effective_ii << ")" << std::endl;
	}
}

int main(int argc, char **argv)
{
	::testing::InitGoogleTest(&argc, argv);
	return RUN_ALL_TESTS();
}
