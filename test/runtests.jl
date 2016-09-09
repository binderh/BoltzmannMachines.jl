using Base.Test

using BoltzmannMachines
const BMs = BoltzmannMachines

include("BMTest.jl")

@test_approx_eq_eps(BMs.bernoulliloglikelihoodbaserate(10),
      BMs.bernoulliloglikelihoodbaserate(rand([0.0 1.0], 10000, 10)), 0.002)

x = rand([0.0 0.0 0.0 1.0 1.0], 1000, 10);

@test_approx_eq_eps(BMTest.bgrbmexactloglikelihoodvsbaserate(x, 10), 0, 1e-10)
@test_approx_eq_eps(BMTest.rbmexactloglikelihoodvsbaserate(x, 10), 0, 1e-10)

nvisible = 10
nhidden = 10
bgrbm = BMs.BernoulliGaussianRBM(zeros(nvisible, nhidden), rand(nvisible), ones(nhidden));

@test_approx_eq(BMs.logpartitionfunction(bgrbm, 1.0),
      BMs.exactlogpartitionfunction(bgrbm))