# Replication code for Caselli, Koren, Lisicky and Tenreyro. 2018. "Diversification Through Trade"
## Data
Data are from []
## Getting started
The code runs Julia 0.6 on Mac OS X and Linux. (We have not tested it on Windows.) The necessary Julia packages are installed by `install.jl` or `make install`.

The `Makefile` runs all the necessary computations in the correct order. If you want to reproduce the tables in our paper, simply run `make` or `make tables`.

Both Julia and Make can run in parallel. Computing the equilibrium for a given set of parameters takes about 1 minute on a single 3.8GHz CPU core. Each period's equilibrium can be computed in parallel (in Julia) and each scenario can be computed in parallel (in Make). With 44 scenarios (see below) and 36 time periods, total run time should be about 1600 minutes. The Makefile is set to run 10 Julia threads in parallel (`PROCS = -p10`). If you have fewer cores, set `PROCS` accordingly.  You can then run Make jobs in parallel with `make -j4 tables`. 

## Workflow
The core logic is in two files.
- `equilibrium.jl` calculates the equilibrium prices and quantities given a set of parameters.
- `calibrate_params.jl` calibrates parameters to match a set of data moments.

These modules are called by each scenario to be computed. An __experiment__ is a set of common parameters applied to our economy *before calibration*. For example, `theta=4` is an experiment and so is `theta=8`. A __scenario__ is a particular (often counterfactual) parametrization of an experiment. For example, given calibrated trade costs `kappa`, a scenario might reset those to their 1972 value.

As an example, consider the following two scenarios: `experiments/CES2/actual/scenario.jl` and `experiments/CES2/kappa1972/scenario.jl`. They belong to the same experiment, `experiments/CES2`, which calibrates its parameters *after* setting `sigma=2` in `experiments/CES2/init_parameters.jl`. 

The `actual` scenario does not change any of the calibrated parameters. The `kappa1972` scenario replaces all `kappa` with the 1972 values in the same country and sector (see `experiments/CES2/kappa1972/change_parameters.jl`).

The results of each run are saved in `results.jld2` (a JLD2 Julia file format) in the _scenario_ folder, such as `experiments/CES2/kappa1972/results.jld2`. Most of our tables require comparisons of four scenarios (with and without trade cost changes, with and without sectoral shocks). These tables are saved in the _experiment_ folder, such as `experiments/CES2/output_table.csv`.

## Technical details
The calibration algorithm is described in Section [] in the paper. The equilibrium solution algorithm is described in Section []. The basic outline of the equilibrium solution can be described by four nested loops.

### Algorithm
- The __outer loop__ solves for equilibrium labor shares, given expected wages. Expectations are taken over `S` possible realizations of future productivity shocks.
- The __adjustment loop__ solves for equilibrium deviations from pre-decided labor shares, in response to shocks to productivity. This only runs when labor adjustment costs are finite, otherwise labor shares remain at their preassigned value.
- The __middle loop__ solves for the equilibrium sectoral expenditure shares using resource constraints and market clearing conditions.
- The __inner loop__ solves for the equilibrium intermediate goods prices across countries, given a _fixed_ set of sectoral expenditure shares. The rest of the prices can be computed algebraically.

### Data structures
All parameters are stored in the dictionary `parameters`. Parameters can vary by m (destination country), n (source country), j (sector) and t (time). They are stored in a 4-dimensional array with indexes (m,n,j,t). If a certain dimension is not relevant for a parameter, that dimension is retained as a singleton dimension. This is to ensure that arrays are conforming to one another in size. 

Similarly, all random variables computed in the equilibrium are stored as 4-dimensional arrays with m, n, j and s (state of the world) as indexes. This ensures conformability of variables and easy formulas such as
```julia
R_nt = sum(w_njt .* L_njt ./ beta_j, 3)
```
where the summation is across the third, j, dimension.