module Environment
	export parameters
	## these are needed for data -> parameters mapping
	parameters = Dict{Symbol, Any}()

	# CES parameters
	parameters[:sigma] = 0.999
	parameters[:theta] = 4.0
	parameters[:eta] = 4.0

	########## parameters common across scenarios
	## these are function of data
	# inverse of adjustment cost, 0 if cannot readjust
	parameters[:one_over_rho] = 0.01

	include("../config.jl")
	# change parameters after reading data, but common across scenarios
	## Trade imbalance
	parameters[:S_nt] = parameters[:S_nt_data]
end