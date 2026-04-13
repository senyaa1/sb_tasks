#pragma once

#include <iostream>
#include <string>
#include <vector>

enum class OpType
{
	kLoad,
	kStore,
	kCompute
};

struct Node
{
	int node_id;
	OpType op_type;
};

struct Edge
{
	int source_id;
	int target_id;
	int weight;
	std::string edge_type;
};

struct Graph
{
	std::vector<Node> nodes;
	std::vector<Edge> edges;
};

struct ScheduleParams
{
	int unroll_factor;
	int ii_numerator;
};

struct ScheduleResult
{
	bool found;
	int unroll_factor;
	int ii_numerator;
	double effective_ii;
};

OpType ParseOpType(const std::string &s);
Graph ReadProblemInstance();
bool SolveIlp(const ScheduleParams &params, const Graph &instance);
ScheduleResult FindBestSchedule(const Graph &instance, int max_unroll_factor, int max_ii_numerator);
void PrintScheduleResult(const ScheduleResult &result);
