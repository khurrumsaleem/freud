from freud import box as bx;
import numpy as np
import numpy.testing as npt
import unittest

class TestBox(unittest.TestCase):
    def test_BoxLength(self):
        box = bx.Box(2, 2, 2, 1, 0, 0)

        Lx = box.getLx()
        Ly = box.getLy()
        Lz = box.getLz()

        npt.assert_almost_equal(Lx, 2, decimal=2, err_msg="LxFail")
        npt.assert_almost_equal(Ly, 2, decimal=2, err_msg="LyFail")
        npt.assert_almost_equal(Lz, 2, decimal=2, err_msg="LzFail")

    def test_TiltFactor(self):
        box = bx.Box(2,	2, 2, 1, 0, 0);

        tiltxy = box.getTiltFactorXY()
        tiltxz = box.getTiltFactorXZ()
        tiltyz = box.getTiltFactorYZ()

        npt.assert_almost_equal(tiltxy, 1, decimal=2, err_msg="TiltXYfail")
        npt.assert_almost_equal(tiltxz, 0, decimal=2, err_msg="TiltXZfail")
        npt.assert_almost_equal(tiltyz, 0, decimal=2, err_msg="TiltYZfail")

    def test_BoxVolume(self):
        box = bx.Box(2, 2, 2, 1, 0, 0)

        volume = box.getVolume()

        npt.assert_almost_equal(volume, 8, decimal=2, err_msg="VolumnFail")

    def test_WrapSingleParticle(self):
        box = bx.Box(2, 2, 2, 1, 0, 0)
        testpoints = np.array([0, -1, -1], dtype=np.float32)
        box.wrap(testpoints)

        npt.assert_almost_equal(testpoints[0], -2, decimal=2, err_msg="WrapFail")

    def test_WrapMultipleParticles(self):
        box = bx.Box(2, 2, 2, 1, 0, 0)
        testpoints = np.array([[0, -1, -1],
                               [0, 0.5, 0]], dtype=np.float32)
        box.wrap(testpoints)

        npt.assert_almost_equal(testpoints[0,0], -2, decimal=2, err_msg="WrapFail")

    def test_WrapMultipleImages(self):
        box = bx.Box(2, 2, 2, 1, 0, 0)
        testpoints = np.array([[10, -5, -5],
                               [0, 0.5, 0]], dtype=np.float32)
        box.wrap(testpoints)

        npt.assert_almost_equal(testpoints[0,0], -2, decimal=2, err_msg="WrapFail")

    def test_unwrap(self):
        box = bx.Box(2, 2, 2, 1, 0, 0)
        testpoints = np.array([[0, -1, -1],
                               [0, 0.5, 0]], dtype=np.float32)
        imgs = np.array([[1,0,0],
                         [1,1,0]], dtype=np.int32)
        box.unwrap(testpoints, imgs)

        npt.assert_almost_equal(testpoints[0,0], 2, decimal=2, err_msg="WrapFail")

    def test_equal(self):
        box = bx.Box(2, 2, 2, 1, 0.5, 0.1)
        box2 = bx.Box(2, 2, 2, 1, 0, 0)
        self.assertEqual(box, box)
        self.assertNotEqual(box, box2)

    def test_dict(self):
        box = bx.Box(2, 2, 2, 1, 0.5, 0.1)
        box.to_dict()

    def test_str(self):
        box = bx.Box(2, 2, 2, 1, 0.5, 0.1)
        box2 = bx.Box(2, 2, 2, 1, 0.5, 0.1)
        self.assertEqual(str(box), str(box2))

    def test_tuple(self):
        box = bx.Box(2, 2, 2, 1, 0.5, 0.1)
        box2 = bx.Box.from_box(box.to_tuple())
        self.assertEqual(box, box)

    def test_from_box(self):
        box = bx.Box(2, 2, 2, 1, 0.5, 0.1)
        box2 = bx.Box.from_box(box)
        self.assertEqual(box, box)

    def test_matrix(self):
        box = bx.Box(2, 2, 2, 1, 0.5, 0.1)
        box2 = box.from_matrix(box.to_matrix())
        self.assertTrue(np.isclose(box.to_matrix(), box2.to_matrix()).all())


if __name__ == '__main__':
    unittest.main()
