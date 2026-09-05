"""Compact 2D RRT* planner used for UAV free-space motion planning."""
from __future__ import annotations
import math, random
from dataclasses import dataclass
from typing import Iterable, List, Tuple

Point = Tuple[float, float]

@dataclass
class Node:
    p: Point
    parent: int | None = None
    cost: float = 0.0

class RRTStar:
    def __init__(self, bounds=(-200.0, 200.0, -200.0, 200.0), step=18.0, radius=42.0, iterations=700, seed=7):
        self.x0, self.x1, self.y0, self.y1 = bounds
        self.step, self.radius, self.iterations = step, radius, iterations
        self.rng = random.Random(seed)

    @staticmethod
    def dist(a: Point, b: Point) -> float: return math.hypot(a[0]-b[0], a[1]-b[1])
    @staticmethod
    def steer(a: Point, b: Point, step: float) -> Point:
        d=RRTStar.dist(a,b)
        if d <= step: return b
        r=step/d
        return (a[0]+(b[0]-a[0])*r, a[1]+(b[1]-a[1])*r)

    def _free(self, p: Point, obstacles: Iterable[Tuple[float,float,float]]) -> bool:
        return self.x0 <= p[0] <= self.x1 and self.y0 <= p[1] <= self.y1 and all(self.dist(p,(ox,oz)) > rr for ox,oz,rr in obstacles)

    def _edge_free(self, a: Point, b: Point, obstacles) -> bool:
        d=self.dist(a,b); n=max(2,int(d/3))
        return all(self._free((a[0]+(b[0]-a[0])*i/n,a[1]+(b[1]-a[1])*i/n),obstacles) for i in range(n+1))

    def plan(self, start: Point, goal: Point, obstacles: Iterable[Tuple[float,float,float]] = ()) -> List[Point]:
        obstacles=list(obstacles)
        if self._edge_free(start,goal,obstacles): return [start,goal]
        if not self._free(start,obstacles) or not self._free(goal,obstacles): return [start,goal]
        nodes=[Node(start)]
        goal_idx=None
        for _ in range(self.iterations):
            sample=goal if self.rng.random()<0.15 else (self.rng.uniform(self.x0,self.x1),self.rng.uniform(self.y0,self.y1))
            nearest=min(range(len(nodes)),key=lambda i:self.dist(nodes[i].p,sample))
            np=self.steer(nodes[nearest].p,sample,self.step)
            if not self._edge_free(nodes[nearest].p,np,obstacles): continue
            near=[i for i,n in enumerate(nodes) if self.dist(n.p,np)<=self.radius and self._edge_free(n.p,np,obstacles)]
            parent=nearest; cost=nodes[nearest].cost+self.dist(nodes[nearest].p,np)
            for i in near:
                c=nodes[i].cost+self.dist(nodes[i].p,np)
                if c<cost: parent,cost=i,c
            nodes.append(Node(np,parent,cost)); ni=len(nodes)-1
            for i in near:
                c=nodes[ni].cost+self.dist(nodes[ni].p,nodes[i].p)
                if c<nodes[i].cost and self._edge_free(nodes[ni].p,nodes[i].p,obstacles):
                    nodes[i].parent=ni; nodes[i].cost=c
            if self.dist(np,goal)<=self.step and self._edge_free(np,goal,obstacles):
                nodes.append(Node(goal,ni,nodes[ni].cost+self.dist(np,goal))); goal_idx=len(nodes)-1; break
        if goal_idx is None:
            return [start,goal]
        path=[]; i=goal_idx
        while i is not None: path.append(nodes[i].p); i=nodes[i].parent
        return list(reversed(path))

rrt_star = RRTStar()
