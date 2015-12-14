from __future__ import division
from numpy import sqrt
import numpy
from freud.shape import ConvexPolyhedron

# Example:
# from freud.shape.ObtuseGoldenRhombohedron import shape
points = [ 
          (-0.9472135954999579, 0.08541019662496847, 0.2628655560595668),
          (-0.5, -0.8090169943749475, 0.2628655560595668),
          (-0.5, 0.8090169943749475, -0.2628655560595668),
          (-0.05278640450004207, -0.08541019662496847, -0.2628655560595668),
          (0.05278640450004207, 0.08541019662496847, 0.2628655560595668),
          (0.5, -0.8090169943749475, 0.2628655560595668),
          (0.5, 0.8090169943749475, -0.2628655560595668),
          (0.9472135954999579, -0.08541019662496847, -0.2628655560595668),
         ]

shape = ConvexPolyhedron(numpy.array(points))