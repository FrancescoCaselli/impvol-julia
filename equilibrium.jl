using Images

include("utils.jl")
parameters = Dict{Symbol, Any}()

# for matrix conformity, store all variables in a 4-dimensional array:
# mnjt: destination, source, sector, time

# per-period random variables are stored as
# mnjs: destination, source, sector, state


function coerce_parameters!(parameters)
	N, J, T = parameters[:N], parameters[:J], parameters[:T]

	parameters[:alpha_jt] = reshape(parameters[:alpha], (1, 1, J, T))
	parameters[:beta_j] = reshape(parameters[:beta], (1, 1, J, 1))
	parameters[:L_nt] = ones(1,N,1,T)

	beta_j = parameters[:beta]'
	gamma_jk = parameters[:gamma_jk]
	parameters[:B_j] = reshape(beta_j .^ (-beta_j) .* prod(gamma_jk .^ (-gamma_jk),2), (1,1,J,1)) 
	# FIXME: use definition of xi parameter
	parameters[:xi] = 1 
end

function non_random_variable(y, t)
	# array coersion is going to take care of rest
	B = y[:,:,:,t]
	return cat(ndims(B)+1, B)
end

function expected_value(y)
	return meanfinite(y, 4)[:,:,:,1]
end

function rotate_sectors(A, y)
	# y may be a time series variable or a random variable
	M, N, J, T = size(y)
	K = size(A,1)
	B = zeros(M,N,K,T)
	for m=1:M
		for n=1:N
			for t=1:T
				B[m,n,:,t] = A * y[m,n,:,t] 
			end
		end
	end
	return B
end

function distance(p1, p2)
	return meanfinite(((log(p1) .- log(p2)) .^ 2)[:], 1)[1] .^ 0.5
end

function free_trade_sector_shares!(parameters)
	N, J, T = parameters[:N], parameters[:J], parameters[:T]
	gamma_jk = parameters[:gamma_jk]
	beta_j = parameters[:beta_j]
	alpha_jt = parameters[:alpha_jt]

	revenue_shares = zeros(1,1,J,T)
	for t=1:T
		revenue_shares[1,1,:,t] = eigen_share(alpha_jt[1,1,:,t]*beta_j[1,1,:,1]' + gamma_jk)
	end
	parameters[:sector_shares] = revenue_shares
end

function input_price_index(sectoral_prices_j, globals)
	gamma_jk = globals[:gamma_jk]
	return prod(sectoral_prices_j .^ gamma_jk, 1)
end

function input_price_index!(random_variables, parameters)
	N, J, S = parameters[:N], parameters[:J], parameters[:S]
	P = random_variables[:P_njs]
	random_variables[:input_price_njs] = Array{Float64}(1,N,J,S)
	rho = random_variables[:input_price_njs]
	for n in 1:N
		for s in 1:S
			p = P[1,n,:,s]
			rho[1,n,:,s] = input_price_index(p, parameters)
		end
	end
end

function compute_price!(random_variables, parameters, t)
	theta = parameters[:theta]
	kappa = non_random_variable(parameters[:kappa_mnjt], t)
	rho_njs = random_variables[:rho_njs]

	random_variables[:P_njs] = array_transpose(sum((rho_njs ./ kappa) .^ (-theta), 2) .^ (-1/theta))
end

function compute_price_index!(random_variables, parameters, t)
	alpha = non_random_variable(parameters[:alpha_jt], t)
	P_njs = random_variables[:P_njs]

	# use formula on p43 of "paper November 8 2017.pdf"
	random_variables[:P_ns] = prod(alpha .^ (-alpha) .* P_njs .^ (alpha), 3)
end

function free_trade_country_shares!(random_variables, L_njt, parameters, t)
	A_njs = random_variables[:A_njs]
	L_nj = non_random_variable(L_njt, t)
	theta = parameters[:theta]
	beta_j = parameters[:beta_j]

	d_njs = A_njs .^ (theta ./ (1 + theta*beta_j)) .* L_nj .^ (theta .* beta_j ./ (1 + theta*beta_j))
	random_variables[:d_njs_free] = d_njs ./ sum(d_njs,2)
end

function free_trade_wages!(random_variables, L_njt, parameters, t)
	free_trade_country_shares!(random_variables, L_njt, parameters, t)
	free_trade_sector_shares!(parameters)

	d_njs = random_variables[:d_njs_free]
	beta_j = parameters[:beta_j]
	E_wt = non_random_variable(parameters[:sector_shares], t)
	L_nj = non_random_variable(L_njt, t)

	random_variables[:w_njs] = beta_j .* d_njs .* E_wt ./ L_nj
end

function free_trade_prices!(random_variables, L_njt, parameters, t)
	free_trade_country_shares!(random_variables, L_njt, parameters, t)
	free_trade_sector_shares!(parameters)
	beta_j = parameters[:beta_j]
	theta = parameters[:theta]
	d_njs = random_variables[:d_njs_free]
	xi = parameters[:xi]
	B_j = parameters[:B_j]
	A_njs = random_variables[:A_njs]
	E_wt = non_random_variable(parameters[:sector_shares], t)
	L_nj = non_random_variable(L_njt, t)
	gamma_jk = parameters[:gamma_jk]

	random_variables[:P_njs] = exp(rotate_sectors(inv(eye(gamma_jk)-gamma_jk), log(xi * d_njs .^(beta_j+1/theta) .* B_j .* (E_wt ./ L_nj) .^(beta_j) ./ A_njs)))
	random_variables[:rho_njs] = random_variables[:P_njs] ./ d_njs .^(1/theta)
end

function compute_import_shares!(random_variables, variables, parameters, t)
	compute_price!(random_variables, parameters, t)

	P_mjs = array_transpose(random_variables[:P_njs])
	theta = parameters[:theta]
	kappa_mnjt = non_random_variable(parameters[:kappa_mnjt], t)
	rho_njs = random_variables[:rho_njs]

	variables[:d_mnjs] = (rho_njs ./ kappa_mnjt ./ P_mjs) .^ (-theta)
end

function compute_wage!(random_variables, parameters)
	input_price_index!(random_variables, parameters)

	rho_njs = random_variables[:rho_njs]
	input_price_njs = random_variables[:input_price_njs]

	beta_j = parameters[:beta_j]
	B_j = parameters[:B_j]
	xi = parameters[:xi]
	# we dont need T
	A_njs = random_variables[:A_njs]

	random_variables[:w_njs] = (rho_njs .* A_njs ./ input_price_njs ./ (xi * B_j)) .^ (1 ./ beta_j)
end

function compute_revenue!(random_variables, L_njt, parameters, t)
	w_njs = random_variables[:w_njs]
	L_nj = non_random_variable(L_njt, t)
	beta_j = parameters[:beta_j]

	random_variables[:R_njs] = w_njs .* L_nj ./ beta_j
end

function compute_expenditure_shares!(random_variables, parameters, t)
	# use eq 19 of "paper November 8 2017.pdf"
	R_nks = random_variables[:R_njs]
	beta_j = parameters[:beta_j]
	gamma_jk = parameters[:gamma_jk]
	alpha_jt = non_random_variable(parameters[:alpha_jt], t)
	S_nt = non_random_variable(parameters[:S_nt], t)
	expenditure = sum(R_nks, 3) .- S_nt

	wagebill_ns = rotate_sectors(beta_j[:]', R_nks)
	intermediate_njs = rotate_sectors(gamma_jk, R_nks)
	random_variables[:e_mjs] = array_transpose((alpha_jt .* wagebill_ns .+ intermediate_njs .- alpha_jt .* S_nt) ./ expenditure)
end

function fixed_expenditure_shares!(random_variables, parameters, t)
	R_mjs = array_transpose(random_variables[:R_njs])	
	expenditure = sum(R_mjs, 3) .- array_transpose(non_random_variable(parameters[:S_nt], t))
	random_variables[:E_mjs] = random_variables[:e_mjs] .* expenditure
end

function shadow_price_step(random_variables, parameters, t)
	theta = parameters[:theta]
	E_mjs = random_variables[:E_mjs]
	R_njs = random_variables[:R_njs]
	kappa_mnjt = non_random_variable(parameters[:kappa_mnjt], t)
	P_mjs = array_transpose(random_variables[:P_njs])

	return sum( (kappa_mnjt .* P_mjs) .^ theta .* E_mjs ./ R_njs, 1) .^ (1/theta)  
end

function starting_values!(random_variables, L_njt, parameters, t)
	free_trade_wages!(random_variables, L_njt, parameters, t)
	free_trade_prices!(random_variables, L_njt, parameters, t)
	compute_revenue!(random_variables, L_njt, parameters, t)
	compute_expenditure_shares!(random_variables, parameters, t)
	fixed_expenditure_shares!(random_variables, parameters, t)
end

function inner_loop!(random_variables, L_njt, parameters, t)
	println("Inner loop")
	lambda = parameters[:lambda]
	dist = 999
	k = 1

	while dist > parameters[:inner_tolerance]
		new_rho = shadow_price_step(random_variables, parameters, t)
		dist = distance(new_rho, random_variables[:rho_njs])
		println("Inner ", k, ": ")
		println(meanfinite(new_rho, 4)[1,1,1,1])
		println(dist)
		random_variables[:rho_njs] = lambda*new_rho + (1-lambda)*random_variables[:rho_njs]
		compute_price!(random_variables, parameters, t)
		compute_wage!(random_variables, parameters)
		compute_revenue!(random_variables, L_njt, parameters, t)
		fixed_expenditure_shares!(random_variables, parameters, t)
		k = k+1
	end
end

function middle_loop!(random_variables, L_njt, parameters, t)
	println("Middle loop")
	starting_values!(random_variables, L_njt, parameters, t)
	dist = 999
	k = 1
	old_expenditure_shares = random_variables[:e_mjs]

	while dist > parameters[:middle_tolerance]
		inner_loop!(random_variables, L_njt, parameters, t)
		compute_expenditure_shares!(random_variables, parameters, t)
		dist = distance(random_variables[:e_mjs], old_expenditure_shares)
		println("Middle ", k, ": ")
		println(meanfinite(random_variables[:e_mjs], 4)[1,1,1,1])
		println(dist)

		old_expenditure_shares = random_variables[:e_mjs]
		k = k+1
	end
end

function expected_wage_share(random_variables, L_njt, t)
	L_nj = non_random_variable(L_njt, t)
	w_njs = random_variables[:w_njs]

	wage_bill = w_njs .* L_nj
	wage_share = wage_bill ./ sum(wage_bill, 3)

	return expected_value(wage_share)
end

function outer_loop!(random_variables, L_njt, parameters, t)
	N, J, S = parameters[:N], parameters[:J], parameters[:S]
	println("Outer loop")
	dist = 999
	k = 1

	while dist > parameters[:outer_tolerance]
		L_nj = non_random_variable(L_njt, t)
		old_wage_share = L_nj ./ sum(L_nj, 3)
		middle_loop!(random_variables, L_njt, parameters, t)
		wage_share = expected_wage_share(random_variables, L_njt, t)

		dist = distance(wage_share, old_wage_share)
		println("Outer ", k, ": ")
		println(dist)

		L_njt[:,:,:,t] = (0.0*old_wage_share + 1.00*wage_share) * J
		k = k+1
	end
end

function period_wrapper(A_njs, L_njt, parameters, t)
	random_variables = Dict{Symbol, Any}()
	random_variables[:A_njs] = A_njs 
	outer_loop!(random_variables, L_njt, parameters, t)
	return random_variables
end

function draw_next_productivity(current_productivity, parameters)
	N, J, S = parameters[:N], parameters[:J], parameters[:S]
	i = rand(1:S)
	random_realization = non_random_variable(current_productivity, i)
	AR_decay = parameters[:AR_decay]
	innovation = parameters[:innovation]
	return random_realization .^ (AR_decay) .* innovation
end

function check_parameters(globals)
	@assert0 sum(globals[:alpha], 2)-1.0
end

N = 2
J = 3
T = 10
S = 1000
fill_dict!(parameters, N=N, J=J, T=T, S=S)

alpha = rand(J) .* ones(J,T)
beta = 0.25 + 0.75 * rand(1, J)
kappa_mnjt = rand(N,N,J,T)
for j=1:J
	for t=1:T
		for n=1:N
			kappa_mnjt[n,n,j,t] = 1.0
		end
	end
end
Z_njt = rand(1,N,J,T)

fill_dict!(parameters, alpha=alpha ./ sum(alpha, 1), beta=beta, theta=4, kappa_mnjt=kappa_mnjt, Z_njt=Z_njt, S_nt=zeros(1,N,1,T))
# make Gamma more diagonal
gamma_jk = rand(J,J) + 1.0*eye(J)
# for testing purposed, set IO links to 0
# test for continuity with small IO links
#parameters[:gamma_jk] = 0.75*eye(J)
#parameters[:gamma_jk] = repmat((1-beta[:]')/J, J, 1)
#parameters[:beta] = 0.25*ones(1,J)
parameters[:gamma_jk] = gamma_jk ./ sum(gamma_jk, 1) .* (1-beta)
# adaptive step size. large lambda means large steps
parameters[:lambda] = exp(-0.05*(J-1)^0.75)
# this is log points of average input price differences
parameters[:inner_tolerance] = 0.001
parameters[:middle_tolerance] = 0.003
parameters[:outer_tolerance] = 0.005

# only draw and store innovations once
# set variance covariance matrix here
parameters[:innovation] = exp(0.1*randn(1,N,J,S))
# AR coefficient for each (n,j)
parameters[:AR_decay] = 0.9*ones(1,N,J,1)

coerce_parameters!(parameters)

A_njs = 1.0 .+ rand(1,N,J,S)
L_njt = ones(1,N,J,T)

for t = 1:T
	@time random_variables = period_wrapper(A_njs, L_njt, parameters, t)
	println("--- ", t, " ---")
	display(L_njt[1,:,:,t])
	println("")
	display(J*expected_wage_share(random_variables, L_njt, t)[1,:,:])
	A_njs = draw_next_productivity(A_njs, parameters)
end