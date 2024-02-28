# Copyright (c) 2010-2023 The Regents of the University of Michigan
# This file is from the freud project, released under the BSD 3-Clause License.

import numpy.testing as npt
import pytest

import freud


class TestLocalDensity:
    """Test fixture for ContinuousCoordination"""

    def setup_method(self):
        """Initialize a box with randomly placed particles"""
        box_size = 10
        num_points = 1000
        self.box, self.pos = freud.data.make_random_system(
            box_size, num_points, seed=123
        )
        # 0.0 is the same as just counting neighbor and can be used for testing
        self.powers = [0.0, 2.0, 4.0, 8.0]
        self.compute_log = True
        self.compute_exp = True
        self.coord = freud.density.ContinuousCoordination(
            self.powers, self.compute_log, self.compute_exp
        )
        self.voronoi = freud.locality.Voronoi()

    def compute(self, system):
        self.voronoi.compute(system)
        self.coord.compute(system, self.voronoi)

    def test_attribute_access(self):
        """Test attribute access before calling compute."""
        assert self.coord.powers == self.powers
        assert self.coord.compute_log
        assert self.coord.compute_exp
        assert self.coord.number_of_coordinations == 6
        with pytest.raises(AttributeError):
            self.coord.coordination

    def test_coordination_random(self):
        """Test for the correct coordination at each point"""
        self.compute((self.box, self.pos))
        # Test attribute access after calling compute
        self.coord.coordination

        npt.assert_allclose(
            self.coord.coordination[:, 0], self.voronoi.nlist.neighbor_counts
        )

    def test_coordination_fcc(self):
        system = freud.data.UnitCell.fcc().generate_system(4)
        self.compute(system)
        npt.assert_allclose(self.coord.coordination, 12.0, rtol=1e-6)

    def test_coordination_sc(self):
        system = freud.data.UnitCell.sc().generate_system(4)
        self.compute(system)
        npt.assert_allclose(self.coord.coordination, 6.0, rtol=1e-6)

    def test_coordination_square(self):
        system = freud.data.UnitCell.square().generate_system(4)
        self.compute(system)
        npt.assert_allclose(self.coord.coordination, 4.0, rtol=1e-6)

    def test_repr(self):
        assert str(self.coord) == str(eval(repr(self.coord)))
