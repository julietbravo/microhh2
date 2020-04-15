Code and compilation
====================

.. toctree::
   :maxdepth: 2
   :caption: Contents:

Requirements
------------

Before starting the tutorial, make sure that you meet the requirements of MicroHH. In order to compile MicroHH you need:

- C++ compiler
- FFTW3 libraries
- NetCDF4-C
- CMake
- MPI2/3 implementation `(optional for MPI support)`
- CUDA `(optional for GPU support)`
- Python + Numpy `(optional for running example cases)`
- Ipython + NetCDF4 + Matplotlib `(optional for plotting results example cases)`

.. note::

    The legacy netCDF C++ and NetCDF-CXX4 libraries are no longer supported (or required), as MicroHH has its own C++ wrapper for the NetCDF4-C library.

If you are running on OSX, please install also the GNU sed (:code:`gnu-sed` in Homebrew, or :code:`gsed` in MacPorts)

Obtaining the MicroHH code
--------------------------

The MicroHH code is hosted at Github (https://github.com/microhh/microhh). The code can either be downloaded as a ZIP file (https://github.com/microhh/microhh/archive/master.zip), but if Git (version control system) is installed, the code can also be downloaded using:

.. code-block:: shell

    git clone https://github.com/microhh/microhh.git

The advantage of using Git is that the model can easily be updated at a later time by calling :code:`git pull` from anywhere in the MicroHH directory.

Compilation of the code
-----------------------

At the starting point of this tutorial, we assume that you are in the main directory of MicroHH. First, we will take care of the configuration file. Enter the config directory:

.. code-block:: shell

    cd config

Here, you find a potential series of settings with the extension :code:`.cmake` for different systems. Check whether your system is there. If not, create a file with the correct compiler settings and the proper location for all libraries. Then, copy your system file to :code:`default.cmake`. Let us assume your system is Ubuntu:

.. code-block:: shell

    cp ubuntu.cmake default.cmake

Then, go back to the main directory and create a subdirectory with an arbitrary name in which you will compile the code. Let us assume this directory is called :code:`build`:

.. code-block:: shell

    cd ..  
    mkdir build  
    cd build   


From this directory, run :code:`cmake` with the suffix :code:`..` to point to the parent directory where the CMakeLists.txt is found. This builds the model without Message Passing Interface (MPI) and CUDA support.

.. code-block:: shell

    cmake ..


In case you prefer to enable either MPI or CUDA (at the moment, not both!), run one of the following commands instead of the previous one:

.. code-block:: shell

    cmake .. -DUSEMPI=TRUE
    cmake .. -DUSECUDA=TRUE

.. warning::

    Once the build has been configured and you wish to change the :code:`USECUDA` or :code:`USEMPI` setting, you must delete the build directory or create an additional empty directory from which :code:`cmake` is run.
    
With the previous command you have triggered the build system and created the :code:`Makefile`, if the :code:`default.cmake` file contains the correct settings. Now, you can start the compilation of the code and create the MicroHH executable with:

.. code-block:: shell

    make -j 4

Your directory should contain a file named :code:`microhh` now. This is the main executable.

