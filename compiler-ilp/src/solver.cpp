#include <iostream>
#include <string>
#include <vector>

#include "ortools/linear_solver/linear_solver.h"
#include "ortools/linear_solver/linear_solver.pb.h"
#include "solver.hpp"

OpType ParseOpType(const std::string &s)
{
	if (s == "load")
	{
		return OpType::kLoad;
	}

	if (s == "store")
	{
		return OpType::kStore;
	}

	return OpType::kCompute;
}

Graph ReadProblemInstance()
{
	Graph instance;
	int num_nodes;
	std::cin >> num_nodes;

	instance.nodes.resize(num_nodes);
	for (int i = 0; i < num_nodes; ++i)
	{
		std::string op;
		std::cin >> op;
		instance.nodes[i] = {i, ParseOpType(op)};
	}

	int num_edges;
	std::cin >> num_edges;
	instance.edges.resize(num_edges);

	for (int i = 0; i < num_edges; ++i)
	{
		std::cin >> instance.edges[i].source_id >> instance.edges[i].target_id >> instance.edges[i].weight >>
		    instance.edges[i].edge_type;
	}

	return instance;
}

bool SolveIlp(const ScheduleParams &params, const Graph &instance)
{
	operations_research::MPSolver solver("SoftwarePipelining",
					     operations_research::MPSolver::SAT_INTEGER_PROGRAMMING);

	const int num_nodes = instance.nodes.size();
	const int unroll_factor = params.unroll_factor;
	const int ii_numerator = params.ii_numerator;

	std::vector<std::vector<operations_research::MPVariable *>> t(
	    num_nodes, std::vector<operations_research::MPVariable *>(unroll_factor));

	std::vector<std::vector<std::vector<operations_research::MPVariable *>>> x(
	    num_nodes, std::vector<std::vector<operations_research::MPVariable *>>(
			   unroll_factor, std::vector<operations_research::MPVariable *>(ii_numerator)));

	for (int i = 0; i < num_nodes; ++i)
	{
		for (int a = 0; a < unroll_factor; ++a)
		{
			t[i][a] = solver.MakeIntVar(0, 1000, "t_" + std::to_string(i) + "_" + std::to_string(a));
			for (int c = 0; c < ii_numerator; ++c)
			{
				x[i][a][c] = solver.MakeIntVar(
				    0, 1, "x_" + std::to_string(i) + "_" + std::to_string(a) + "_" + std::to_string(c));
			}
		}
	}

	for (int i = 0; i < num_nodes; ++i)
	{
		for (int a = 0; a < unroll_factor; ++a)
		{
			operations_research::MPConstraint *one_cycle = solver.MakeRowConstraint(1, 1);
			for (int c = 0; c < ii_numerator; ++c)
			{
				one_cycle->SetCoefficient(x[i][a][c], 1);
			}

			operations_research::MPVariable *k =
			    solver.MakeIntVar(0, 1000, "k_" + std::to_string(i) + "_" + std::to_string(a));
			operations_research::MPConstraint *time_link = solver.MakeRowConstraint(0, 0);
			time_link->SetCoefficient(t[i][a], 1);
			time_link->SetCoefficient(k, -ii_numerator);
			for (int c = 0; c < ii_numerator; ++c)
			{
				time_link->SetCoefficient(x[i][a][c], -c);
			}
		}
	}

	for (const auto &e : instance.edges)
	{
		const int delay = (e.edge_type == "dd") ? e.weight : 0;
		const int dist = (e.edge_type == "ld") ? e.weight : 0;

		for (int a = 0; a < unroll_factor; ++a)
		{
			const int b = (a + dist) % unroll_factor;
			const int dist_prime = (a + dist) / unroll_factor;

			operations_research::MPConstraint *dep =
			    solver.MakeRowConstraint(delay - dist_prime * ii_numerator, solver.infinity());
			dep->SetCoefficient(t[e.target_id][b], 1);
			dep->SetCoefficient(t[e.source_id][a], -1);
		}
	}

	for (int c = 0; c < ii_numerator; ++c)
	{
		operations_research::MPConstraint *res_load = solver.MakeRowConstraint(0, 1);
		operations_research::MPConstraint *res_store = solver.MakeRowConstraint(0, 1);
		operations_research::MPConstraint *res_alu = solver.MakeRowConstraint(0, 1);

		for (int i = 0; i < num_nodes; ++i)
		{
			for (int a = 0; a < unroll_factor; ++a)
			{
				switch (instance.nodes[i].op_type)
				{
					case OpType::kLoad:
						res_load->SetCoefficient(x[i][a][c], 1);
						break;
					case OpType::kStore:
						res_store->SetCoefficient(x[i][a][c], 1);
						break;
					case OpType::kCompute:
						res_alu->SetCoefficient(x[i][a][c], 1);
						break;
				}
			}
		}
	}

	operations_research::MPObjective *objective = solver.MutableObjective();
	for (int i = 0; i < num_nodes; ++i)
	{
		for (int a = 0; a < unroll_factor; ++a)
		{
			objective->SetCoefficient(t[i][a], 1);
		}
	}
	objective->SetMinimization();

	return solver.Solve() == operations_research::MPSolver::OPTIMAL;
}

ScheduleResult FindBestSchedule(const Graph &instance, int max_unroll_factor, int max_ii_numerator)
{
	ScheduleResult best_result{false, -1, -1, 1e9};

	for (int ii_num = 1; ii_num <= max_ii_numerator; ++ii_num)
	{
		for (int uf = 1; uf <= max_unroll_factor; ++uf)
		{
			const double current_ii = static_cast<double>(ii_num) / uf;
			if (current_ii >= best_result.effective_ii)
			{
				continue;
			}

			ScheduleParams params{uf, ii_num};
			if (SolveIlp(params, instance))
			{
				best_result.found = true;
				best_result.effective_ii = current_ii;
				best_result.unroll_factor = uf;
				best_result.ii_numerator = ii_num;
			}
		}
	}

	return best_result;
}

void PrintScheduleResult(const ScheduleResult &result)
{
	if (!result.found)
	{
		std::cout << "No valid schedule found within search limits." << std::endl;
		return;
	}

	std::cout << "II = " << result.ii_numerator << "/" << result.unroll_factor << " (" << result.effective_ii << ")"
		  << std::endl;
	std::cout << "UF = " << result.unroll_factor << std::endl;
}
