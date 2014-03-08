/*
 * MicroHH
 * Copyright (c) 2011-2013 Chiel van Heerwaarden
 * Copyright (c) 2011-2013 Thijs Heus
 *
 * This file is part of MicroHH
 *
 * MicroHH is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * MicroHH is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with MicroHH.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef BUDGET
#define BUDGET

#include <string>

// forward declarations to reduce compilation time
class cmodel;
class cinput;
class cstats;
class cgrid;
class cfields;

class cbudget
{
  public:
    cbudget(cmodel *);
    ~cbudget();

    int readinifile(cinput *);
    int init();
    int create();
    int execstats();

  private:
    cmodel  *model;
    cstats  *stats;
    cgrid   *grid;
    cfields *fields;

    std::string swbudget;

    double *umodel, *vmodel;

    int calctkebudget(double *, double *, double *, double *,
                      double *, double *,
                      double *, double *,
                      double *, double *, double *,
                      double *, double *, double *, double *,
                      double *, double *, double *, double *,
                      double *, double *, double *, double *,
                      double *, double *,
                      double *, double *, double *,
                      double *, double *, double);
    int calctkebudget_buoy(double *, double *, double *, double *);
};
#endif