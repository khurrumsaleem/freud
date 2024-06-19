# Copyright (c) 2010-2024 The Regents of the University of Michigan
# This file is from the freud project, released under the BSD 3-Clause License.

import numpy as np
from benchmark import Benchmark
from benchmarker import run_benchmarks

import freud


class BenchmarkLocalityAABBQuery(Benchmark):
    def __init__(self, L, r_max):
        self.L = L
        self.r_max = r_max

    def bench_setup(self, N):
        self.box = freud.box.Box.cube(self.L)
        seed = 0
        np.random.seed(seed)
        self.points = np.random.uniform(-self.L / 2, self.L / 2, (N, 3))

    def bench_run(self, N):
        aq = freud.locality.AABBQuery(self.box, self.points)
        aq.query(self.points, {"r_max": self.r_max, "exclude_ii": True})


def run():
    Ns = [1000, 10000]
    r_max = 0.5
    L = 10
    number = 100

    name = "freud.locality.AABBQuery"
    return run_benchmarks(
        name, Ns, number, BenchmarkLocalityAABBQuery, L=L, r_max=r_max
    )


if __name__ == "__main__":
    run()
