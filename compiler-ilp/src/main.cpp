#include "solver.hpp"

int main()
{
	Graph instance = ReadProblemInstance();

	constexpr int kMaxUnrollFactor = 4;
	constexpr int kMaxIiNumerator = 10;

	ScheduleResult result = FindBestSchedule(instance, kMaxUnrollFactor, kMaxIiNumerator);
	PrintScheduleResult(result);

	return 0;
}
