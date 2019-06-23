#!/bin/bash

export DEBIAN_FRONTEND="noninteractive"
export LANG="C"
DEBIAN=1
RPM=1
DEPS_STAGE=0
BUILD_STAGE=0
SIGN_STAGE=0
UPLOAD_STAGE=0
BOOTSTRAP=0
ARM=0
DIST=0
UPDATE_HYPERSCAN=0
BUNDLED_LUAJIT=0
UPDATE_LUAJIT=0
NO_OPT=0
JOBS=2
EXTRA_OPT=0
CMAKE=cmake
C_COMPILER=gcc
CXX_COMPILER=g++
NO_DELETE=0
NO_I386=1
LOG="./rspamd_build.log"

usage()
{
  echo "Rspamd build packages script"
  echo ""
  echo "./rspamd_build.sh"
  echo "\t-h --help"
  echo "\t--all: do all stages"
  echo "\t--deb: build debian packages"
  echo "\t--rpm: build rpm packages"
  echo "\t--stable: build stable packages"
  echo "\t--deps: install dependencies"
  echo "\t--build: do build step"
  echo "\t--sign: do sign step"
  echo "\t--upload: upload packages using ssh"
  echo "\t--upload-host: use the following upload host"
  echo "\t--no-inc: do not increase version for rolling release"
  echo "\t--no-i386: do not build packages for i386"
  echo "\t--no-rspamd: do not build rspamd packages"
  echo "\t--no-hyperscan: do not use hyperscan"
  echo "\t--no-luajit: do not use luajit (implies --no-torch)"
  echo "\t--no-torch: do not use torch"
  echo "\t--no-jemalloc: do not use jemalloc"
  echo "\t--no-opt: disable all optimizations"
  echo "\t--no-delete: do not delete old files during rsync"
  echo "\t--extra-opt: enable extra optimizations"
  echo "\t--bootstrap: bootstrap the specified distros"
  echo "\t--arm <dir>: use arm deb packages from specified directory"
  echo "\t--dist: touch the specified dist only"
  echo "\t--update-hyperscan: update (and recompile) hyperscan version"
  echo "\t--jobs: number of jobs to parallel processing (default: 2)"
  echo "\t--bundled-luajit: enable bundled luajit (version 2.1)"
  echo "\t--update-luajit: update bundled luajit (2.1 branch)"
  echo ""
}

while [ "$1" != "" ]; do
  PARAM=`echo $1 | awk -F= '{print $1}'`
  VALUE=`echo $1 | awk -F= '{print $2}'`
  case $PARAM in
    -h | --help)
      usage
      exit
      ;;
    --deb)
      DEBIAN=1
      ;;
    --no-deb)
      DEBIAN=0
      ;;
    --rpm)
      RPM=1
      ;;
    --no-rpm)
      RPM=0
      ;;
    --stable)
      export STABLE=1
      ;;
    --all)
      DEPS_STAGE=1
      BUILD_STAGE=1
      SIGN_STAGE=1
      UPLOAD_STAGE=1
      ;;
    --deps)
      DEPS_STAGE=1
      ;;
    --build)
      BUILD_STAGE=1
      ;;
    --sign)
      SIGN_STAGE=1
      ;;
    --upload)
      UPLOAD_STAGE=1
      ;;
    --no-inc)
      NO_INC=1
      ;;
    --no-i386)
      NO_I386=1
      ;;
    --no-rspamd)
      NO_RSPAMD=1
      ;;
    --no-hyperscan)
      NO_HYPERSCAN=1
      ;;
    --no-luajit)
      NO_LUAJIT=1
      NO_TORCH=1
      ;;
    --no-torch)
      NO_TORCH=1
      ;;
    --no-jemalloc)
      NO_JEMALLOC=1
      ;;
    --no-opt)
      NO_OPT=1
      ;;
    --no-delete)
      NO_DELETE=1
      ;;
    --extra-opt)
      EXTRA_OPT=1
      ;;
    --upload-host)
      UPLOAD_HOST="${VALUE}"
      ;;
    --bootstrap)
      BOOTSTRAP=1
      ;;
    --arm)
      ARM="${VALUE}"
      ;;
    --dist)
      DIST=1
      DISTS="${VALUE}"
      ;;
    --update-hyperscan)
      UPDATE_HYPERSCAN=1
      ;;
    --jobs)
      JOBS="${VALUE}"
      ;;
    --bundled-luajit)
      BUNDLED_LUAJIT=1
      ;;
    --update-luajit)
      UPDATE_LUAJIT=1
      BUNDLED_LUAJIT=1
      ;;
    *)
      echo "ERROR: unknown parameter \"$PARAM\""
      usage
      exit 1
      ;;
  esac
  shift
done

. ./config.sh

DISTRIBS_RPM_FULL="${DISTRIBS_RPM}"

rm ${LOG}

if [ ${BOOTSTRAP} -eq 1 ] ; then
  # We can bootstrap merely debian distros now
  for d in $DISTRIBS_DEB ; do
    _distro=`echo $d | cut -d'-' -f 1`
    _ver=`echo $d | cut -d'-' -f 2`

    case $_distro in
      ubuntu)
        debootstrap \
          --variant=buildd \
          --arch=${MAIN_ARCH} \
          $_ver \
          ${HOME}/$d \
          http://ports.ubuntu.com/
        ;;
      debian)
        debootstrap \
          --variant=buildd \
          --arch=${MAIN_ARCH} \
          $_ver \
          ${HOME}/$d \
          http://httpredir.debian.org/debian/
        ;;
    esac
  done
fi

if [ ${DIST} -ne 0 ] ; then
  _found=0
  DEBIAN=0
  RPM=0
  for d in $DISTRIBS_DEB ; do
    if [ "$d" = "${DISTS}" ] ; then
      DEBIAN=1
      DISTRIBS_DEB="$d"
      _found=1
    fi
  done
  for d in $DISTRIBS_RPM ; do
    if [ "$d" = "${DISTS}" ] ; then
      RPM=1
      DISTRIBS_RPM="$d"
      _found=1
    fi
  done

  if [ $_found -eq 0 ] ; then
    echo "Unknown --dist: $DISTS"
    exit 1
  fi
fi

get_rspamd() {
  rm -fr ${HOME}/rspamd ${HOME}/rspamd.build
  git clone --recursive https://github.com/vstakhov/rspamd ${HOME}/rspamd

  if [ -n "${STABLE}" ] ; then
    ( cd ${HOME}/rspamd && git checkout ${RSPAMD_VER} )

    if [ $? -ne 0 ] ; then
      exit 1
    fi
    
    if [ -d ${HOME}/patches-stable/ ] ; then
      shopt -s nullglob
      for p in ${HOME}/patches-stable/* ; do
        echo "Applying patch $p"
        ( cd ${HOME}/rspamd && patch -p1 < $p )
        if [ $? -ne 0 ] ; then
          exit 1
        fi
      done
    fi
  fi

  ( mkdir ${HOME}/rspamd.build ; cd ${HOME}/rspamd.build ; cmake ${HOME}/rspamd ; make dist )
  if [ $? -ne 0 ] ; then
    exit 1
  fi

  if [ $DEBIAN -ne 0 ] ; then
    for d in $DISTRIBS_DEB ; do
      cp ${HOME}/rspamd.build/rspamd-${RSPAMD_VER}.tar.xz ${HOME}/$d/
      cp ${HOME}/rspamd.build/rspamd-${RSPAMD_VER}.tar.xz ${HOME}/$d-i386/
    done
  fi
  if [ $RPM -ne 0 ] ; then
    for d in $DISTRIBS_RPM ; do
      cp ${HOME}/rspamd.build/rspamd-${RSPAMD_VER}.tar.xz ${HOME}/$d/
      cp ${HOME}/$d/rspamd-${RSPAMD_VER}.tar.xz ${HOME}/$d/${BUILD_DIR}/SOURCES
    done
  fi
}


dep_deb() {
  d=$1
  #rm -fr ${HOME}/$d/opt/hyperscan
  rm -f ${HOME}/$d/*.deb
  rm -f ${HOME}/$d/*.debian.tar.gz
  rm -f ${HOME}/$d/*.changes
  rm -f ${HOME}/$d/*.dsc
  rm -f ${HOME}/$d/*.build
  rm -f ${HOME}/$d/*.orig.tar.*z
  rm -f ${HOME}/$d/*.debian.tar.*z
  rm -f ${HOME}/$d/*.buildinfo

  chroot ${HOME}/$d "/usr/bin/apt-get" update
  chroot ${HOME}/$d "/usr/bin/apt-get" upgrade -y
  chroot ${HOME}/$d "/usr/bin/apt-get" install -y --no-install-recommends ${REAL_DEPS}
  if [ -n "${HYPERSCAN}" -a -z "${NO_HYPERSCAN}" ] ; then
    echo $d | grep 'i386' > /dev/null
    if [ $? -ne 0 ] ; then
      if [ ${UPDATE_HYPERSCAN} -ne 0 ] ; then
        rm -fr ${HOME}/$d/opt/hyperscan
      fi
      if [ ! -d ${HOME}/$d/opt/hyperscan ] ; then
        rm -fr ${HOME}/$d/hyperscan ${HOME}/$d/hyperscan.build
        chroot ${HOME}/$d "/usr/bin/git" clone https://github.com/01org/hyperscan.git
        chroot ${HOME}/$d "sed" -i -e 's/add_subdirectory/#add_subdirectory/' hyperscan/CMakeLists.txt  
        if [ $? -ne 0 ] ; then
          exit 1
        fi
        curl 'ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.41.tar.gz' > ${HOME}/$d/pcre-8.41.tar.gz
        echo "add_subdirectory(chimera)" >> ${HOME}/$d/hyperscan/CMakeLists.txt
        ( cd ${HOME}/$d/hyperscan/ ; tar xzf ${HOME}/$d/pcre-8.41.tar.gz )
        chroot ${HOME}/$d "sed" -i -e 's/CMAKE_POLICY/#CMAKE_POLICY/' hyperscan/pcre-8.41/CMakeLists.txt  
        ( cd ${HOME}/$d ; tar xzf ${HOME}/boost.tar.gz )
        mkdir ${HOME}/$d/hyperscan.build
        chroot ${HOME}/$d "/bin/sh" -c "cd /hyperscan.build ; cmake \
          -DCMAKE_INSTALL_PREFIX=/opt/hyperscan \
          -DBOOST_ROOT=/boost_1_59_0 \
          -DCMAKE_BUILD_TYPE=Release \
          -DFAT_RUNTIME=ON \
          -DCMAKE_C_FLAGS=\"-fpic -fPIC\" \
          -DCMAKE_CXX_FLAGS=\"-fPIC -fpic\" \
          -DCMAKE_C_COMPILER=${SPECIFIC_C_COMPILER} \
          -DCMAKE_CXX_COMPILER=${SPECIFIC_CXX_COMPILER} \
          -DPCRE_SUPPORT_LIBBZ2=OFF \
          /hyperscan && \
          make -j4 && make install/strip"
        if [ $? -ne 0 ] ; then
          exit 1
        fi
      else
        # cleanup build
        rm -fr ${HOME}/$d/hyperscan ${HOME}/$d/hyperscan.build ${HOME}/$d/boost_1_59_0 || true
      fi
    fi
  fi
  if [ "${UPDATE_LUAJIT}" -eq 1 ] ; then
    rm -fr ${HOME}/$d/luajit/ ${HOME}/$d/luajit-src
    chroot ${HOME}/$d "/usr/bin/git" clone -b v2.1 https://luajit.org/git/luajit-2.0.git /luajit-src
    if [ $? -ne 0 ] ; then
      exit 1
    fi
    chroot ${HOME}/$d "/bin/sh" -c "cd /luajit-src && make clean && make CC=\"${SPECIFIC_C_COMPILER} -fPIC\" BUILDMODE=static PREFIX=/luajit && echo yes > .build_done"
    if [ ! -f ${HOME}/$d/luajit-src/.build_done ] ; then
      echo "luajit build failure"
      exit 1
    fi
    chroot ${HOME}/$d "/bin/sh" -c "cd /luajit-src && make CC=\"${SPECIFIC_C_COMPILER} -fPIC\" PREFIX=/luajit BUILDMODE=static install && echo yes > .install_done"
    if [ ! -f ${HOME}/$d/luajit-src/.install_done ] ; then
      echo "luajit install failure"
      exit 1
    fi
    # Avoid dynamic libraries
    rm -f ${HOME}/$d/luajit/lib/*.so
  fi
}

dep_rpm() {
  d=$1
  #rm -fr ${HOME}/$d/opt/hyperscan
  rm -f ${HOME}/$d/*.deb
  rm -f ${HOME}/$d/*.debian.tar.gz
  rm -f ${HOME}/$d/*.changes
  rm -f ${HOME}/$d/*.dsc
  rm -f ${HOME}/$d/*.build
  rm -f ${HOME}/$d/*.orig.tar.*z
  rm -f ${HOME}/$d/*.debian.tar.*z
  rm -f ${HOME}/$d/*.buildinfo

  chroot ${HOME}/$d ${YUM} update
  chroot ${HOME}/$d ${YUM} install ${REAL_DEPS}
  chroot ${HOME}/$d ${YUM} install ${CMAKE}
  if [ $? -ne 0 ] ; then
    exit 1
  fi

  if [ -n "${HYPERSCAN}" -a -z "${NO_HYPERSCAN}" ] ; then
    echo $d | grep 'i386' > /dev/null
    if [ $? -ne 0 ] ; then
      if [ ${UPDATE_HYPERSCAN} -ne 0 ] ; then
        rm -fr ${HOME}/$d/opt/hyperscan
      fi
      if [ ! -d ${HOME}/$d/opt/hyperscan ] ; then
        rm -fr ${HOME}/$d/hyperscan ${HOME}/$d/hyperscan.build
        chroot ${HOME}/$d "/usr/bin/git" clone https://github.com/01org/hyperscan.git
        if [ $? -ne 0 ] ; then
          exit 1
        fi
        ( cd ${HOME}/$d ; tar xzf ${HOME}/boost.tar.gz )
        mkdir ${HOME}/$d/hyperscan.build
        chroot ${HOME}/$d "/bin/sh" -c "cd /hyperscan.build ; if [ -n \"${DEVTOOLSET_ENABLE}\" ] ; then source ${DEVTOOLSET_ENABLE}  ; fi ; ${CMAKE}  \
          ../hyperscan -DCMAKE_INSTALL_PREFIX=/opt/hyperscan \
          -DBOOST_ROOT=/boost_1_59_0 \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_C_FLAGS=\"-fpic -fPIC -march=core2\" \
          -DCMAKE_CXX_FLAGS=\"-fPIC -fpic -march=core2\" \
          && make -j4 && make install"
        if [ $? -ne 0 ] ; then
          exit 1
        fi
      else
        # cleanup build
        rm -fr ${HOME}/$d/hyperscan ${HOME}/$d/hyperscan.build ${HOME}/$d/boost_1_59_0 || true
      fi
    fi
  fi
  if [ "${UPDATE_LUAJIT}" -eq 1 ] ; then
    rm -fr ${HOME}/$d/luajit/ ${HOME}/$d/luajit-src
    chroot ${HOME}/$d "/usr/bin/git" clone -b v2.1 https://luajit.org/git/luajit-2.0.git /luajit-src
    if [ $? -ne 0 ] ; then
      exit 1
    fi
    chroot ${HOME}/$d "/bin/sh" -c "cd /luajit-src && if [ -n \"${DEVTOOLSET_ENABLE}\" ] ; then source ${DEVTOOLSET_ENABLE} ; fi && make clean && make CC=\"gcc -fPIC\" PREFIX=/luajit && make install PREFIX=/luajit"
    if [ $? -ne 0 ] ; then
      exit 1
    fi
    # Avoid dynamic libraries
    rm -f ${HOME}/$d/luajit/lib/*.so
  fi

  chroot ${HOME}/$d rm -fr ${BUILD_DIR}
  chroot ${HOME}/$d mkdir ${BUILD_DIR} \
    ${BUILD_DIR}/RPMS \
    ${BUILD_DIR}/RPMS/i386 \
    ${BUILD_DIR}/RPMS/${MAIN_ARCH} \
    ${BUILD_DIR}/SOURCES \
    ${BUILD_DIR}/SPECS \
    ${BUILD_DIR}/SRPMS
  cp ${HOME}/rpm/SPECS/rspamd.spec ${HOME}/$d/${BUILD_DIR}/SPECS
  cp ${HOME}/rpm/SOURCES/* ${HOME}/$d/${BUILD_DIR}/SOURCES
}

if [ $DEPS_STAGE -eq 1 ] ; then
  if [ -z "${NO_LUAJIT}" ] ; then
    if [ $BUNDLED_LUAJIT -ne 0 ] ; then
      LUAJIT_DEP=""
    else
      LUAJIT_DEP="libluajit-5.1-dev"
    fi
  else
    LUAJIT_DEP="liblua5.1-dev"
  fi

  if [ $DEBIAN -ne 0 ] ; then
    for d in $DISTRIBS_DEB ; do
      HYPERSCAN=""
        SPECIFIC_C_COMPILER="${C_COMPILER}"
        SPECIFIC_CXX_COMPILER="${CXX_COMPILER}"
      grep universe ${HOME}/$d/etc/apt/sources.list > /dev/null 2>&1
      if [ $? -ne 0 ] ; then
        sed -e 's/main/main universe/' ${HOME}/$d/etc/apt/sources.list > /tmp/.tt
        mv /tmp/.tt ${HOME}/$d/etc/apt/sources.list
      fi


      case $d in
        debian-jessie) 
          SPECIFIC_C_COMPILER="clang-6.0"
          SPECIFIC_CXX_COMPILER="clang++-6.0"
          REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP} libgd-dev libblas-dev liblapack-dev libunwind-dev" 
          HYPERSCAN="yes"
          ;;
        debian-stretch) REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP} libgd-dev libblas-dev liblapack-dev libunwind-dev" HYPERSCAN="yes";;
        debian-sid) REAL_DEPS="$DEPS_DEB dh-systemd build-essential ${LUAJIT_DEP} libgd-dev libblas-dev liblapack-dev libunwind-dev" HYPERSCAN="yes";;
        debian-wheezy) REAL_DEPS="$DEPS_DEB liblua5.1-dev libgd2-noxpm-dev libunwind7-dev" ;;
        ubuntu-precise) REAL_DEPS="$DEPS_DEB ${LUAJIT_DEP} libgd2-noxpm-dev libunwind8-dev" ;;
        ubuntu-xenial) 
          SPECIFIC_C_COMPILER="clang-6.0"
          SPECIFIC_CXX_COMPILER="clang++-6.0"
          REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP} libgd-dev libblas-dev liblapack-dev libunwind-dev" 
          HYPERSCAN="yes"
          ;;
        ubuntu-bionic) 
          REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP} libgd-dev libblas-dev liblapack-dev libunwind-dev" 
          HYPERSCAN="yes"
          ;;
        ubuntu-trusty)
          SPECIFIC_C_COMPILER="clang-6.0"
          SPECIFIC_CXX_COMPILER="clang++-6.0"
          REAL_DEPS="$DEPS_DEB ${LUAJIT_DEP} libgd-dev libopenblas-dev liblapack-dev libunwind8-dev"
          HYPERSCAN="yes"
          ;;
        ubuntu-*)
          REAL_DEPS="$DEPS_DEB ${LUAJIT_DEP} libgd-dev libopenblas-dev liblapack-dev libunwind-dev"
          HYPERSCAN="yes"
          ;;
        *) REAL_DEPS="$DEPS_DEB ${LUAJIT_DEP}" HYPERSCAN="yes" ;;
      esac

      dep_deb $d

      ### i386 ###
      if [ -z "${NO_I386}" ] ; then
        d="$d-i386"
        dep_deb $d
      fi
    done
  fi

  if [ $RPM -ne 0 ] ; then
    if [ -z "${NO_LUAJIT}" ] ; then
      if [ $BUNDLED_LUAJIT -ne 0 ] ; then
        LUAJIT_DEP=""
      else
        LUAJIT_DEP="luajit-devel"
      fi
    else
      LUAJIT_DEP="lua-devel"
    fi

    for d in $DISTRIBS_RPM ; do
        HYPERSCAN=""
        CMAKE="cmake"
        SPECIFIC_C_COMPILER="${C_COMPILER}"
        SPECIFIC_CXX_COMPILER="${CXX_COMPILER}"
        DEVTOOLSET_ENABLE=""


        case $d in
          opensuse-*)
            REAL_DEPS="$DEPS_RPM lua-devel sqlite-devel libopendkim-devel ragel gcc-c++"
            YUM="zypper -n"
            HYPERSCAN="yes"
            ;;
          fedora-25*)
            REAL_DEPS="$DEPS_RPM ${LUAJIT_DEP} sqlite-devel libopendkim-devel ragel gcc-c++"
            YUM="dnf --nogpgcheck -y"
            HYPERSCAN="yes"
            ;;
          centos-6)
            HYPERSCAN="yes"
            DEVTOOLSET_ENABLE="/opt/rh/devtoolset-6/enable"
            REAL_DEPS="$DEPS_RPM lua-devel sqlite-devel libopendkim-devel"
            CMAKE="cmake3"
            YUM="yum -y"
            ;;
          centos-7)
            HYPERSCAN="yes"
            DEVTOOLSET_ENABLE="/opt/rh/devtoolset-7/enable"
            CMAKE="cmake3"
            REAL_DEPS="$DEPS_RPM ${LUAJIT_DEP} sqlite-devel libopendkim-devel"
            YUM="yum -y"
            ;;
          *)
            YUM="yum -y"
            REAL_DEPS="$DEPS_RPM sqlite-devel ${LUAJIT_DEP}" ;;
        esac

      dep_rpm $d

      ### i386 ###
      if [ -z "${NO_I386}" ] ; then
        d="$d-i386"
        #dep_rpm $d
      fi
    done
  fi

  if [ -z "${NO_RSPAMD}" ] ; then
    get_rspamd
  fi

fi

build_rspamd_deb() {
  d=$1

  echo "******* BUILD RSPAMD ${RSPAMD_VER} FOR $d ********"

  _id=`git -C ${HOME}/rspamd rev-parse --short HEAD`
  _distname=`echo $d | sed -r -e 's/ubuntu-|debian-//' -e 's/-i386//'`
  _deps_line=`echo ${REAL_DEPS} | tr ' ' ','`
  if [ -n "${STABLE}" ] ; then
    RULES_SED="${RULES_SED} -e \"s/-DDEBIAN_BUILD=1/-DDEBIAN_BUILD=1 -DCMAKE_C_COMPILER=${SPECIFIC_C_COMPILER} -DCMAKE_CXX_COMPILER=${SPECIFIC_CXX_COMPILER}/\""
  else
    RULES_SED="${RULES_SED} -e \"s/-DDEBIAN_BUILD=1/-DDEBIAN_BUILD=1 -DGIT_ID=${_id} -DCMAKE_C_COMPILER=${SPECIFIC_C_COMPILER} -DCMAKE_CXX_COMPILER=${SPECIFIC_CXX_COMPILER}/\""
  fi
  if [ -n "${NO_LUAJIT}" ] ; then
    RULES_SED="${RULES_SED} -e \"s/-DENABLE_LUAJIT=ON/-DENABLE_LUAJIT=OFF/\""
  else
    if [ "${BUNDLED_LUAJIT}" -eq 1 ] ; then
      RULES_SED="${RULES_SED} -e \"s/-DENABLE_LUAJIT=ON/-DENABLE_LUAJIT=ON -DLUA_ROOT=\/luajit/\""
    fi
  fi
  if [ -n "${NO_TORCH}" ] ; then
    RULES_SED="${RULES_SED} -e \"s/-DENABLE_TORCH=ON/-DENABLE_TORCH=OFF/\""
  fi
  if [ -n "${NO_JEMALLOC}" ] ; then
    RULES_SED="${RULES_SED} -e \"s/-DENABLE_JEMALLOC=ON/-DENABLE_JEMALLOC=OFF/\""
  fi
  if [ ${NO_OPT} -eq 1 ] ; then
    RULES_SED="${RULES_SED} -e \"s/-DENABLE_FULL_DEBUG=OFF/-DENABLE_FULL_DEBUG=ON/\""
  fi
  if [ ${EXTRA_OPT} -eq 1 ] ; then
    if [ $_distname != 'wheezy' ] ; then
      # Wheezy is shit
      RULES_SED="${RULES_SED} -e \"s/-DENABLE_OPTIMIZATION=OFF/-DENABLE_OPTIMIZATION=ON/\""
    fi
  fi
  chroot ${HOME}/$d sh -c "rm -fr rspamd-${RSPAMD_VER} ; tar xvf rspamd-${RSPAMD_VER}.tar.xz"
  chroot ${HOME}/$d sh -c "cp rspamd-${RSPAMD_VER}.tar.xz rspamd_${RSPAMD_VER}.orig.tar.xz"
  chroot ${HOME}/$d sh -c "sed -e \"s/Build-Depends:.*/Build-Depends: ${_deps_line}/\" -e \"s/Maintainer:.*/Maintainer: Vsevolod Stakhov <vsevolod@highsecure.ru>/\" < rspamd-${RSPAMD_VER}/debian/control > /tmp/.tt ; mv /tmp/.tt rspamd-${RSPAMD_VER}/debian/control"
  if [ -n "${STABLE}" ] ; then
    chroot ${HOME}/$d sh -c "sed -e \"s/unstable/${_distname}/\" \
      -e \"s/Mikhail Gusarov <dottedmag@debian.org>/Vsevolod Stakhov <vsevolod@highsecure.ru>/\" \
      -e \"s/1.0.2/${RSPAMD_VER}-${_version}~${_distname}/\" < rspamd-${RSPAMD_VER}/debian/changelog > /tmp/.tt ; \
      mv /tmp/.tt rspamd-${RSPAMD_VER}/debian/changelog"
  else
    chroot ${HOME}/$d sh -c "sed -e \"s/unstable/${_distname}/\" \
      -e \"s/Mikhail Gusarov <dottedmag@debian.org>/Vsevolod Stakhov <vsevolod@highsecure.ru>/\" \
      -e \"s/1.0.2/${RSPAMD_VER}-0~git${_version}~${_id}~${_distname}/\" \
      < rspamd-${RSPAMD_VER}/debian/changelog > /tmp/.tt ; \
      mv /tmp/.tt rspamd-${RSPAMD_VER}/debian/changelog"
  fi
  if [ -n "$RULES_SED" ] ; then
    chroot ${HOME}/$d sh -c "sed ${RULES_SED} < rspamd-${RSPAMD_VER}/debian/rules > /tmp/.tt ; \
      mv /tmp/.tt rspamd-${RSPAMD_VER}/debian/rules"
  fi
  chroot ${HOME}/$d sh -c "sed -e 's/native/quilt/' < rspamd-${RSPAMD_VER}/debian/source/format > /tmp/.tt ; \
    mv /tmp/.tt rspamd-${RSPAMD_VER}/debian/source/format"
  rm -f ${HOME}/$d/build.stamp
  if [ ${NO_OPT} -eq 1 ] ; then
    chroot ${HOME}/$d sh -c "cd rspamd-${RSPAMD_VER} ; (DEBUILD_LINTIAN=no DEB_CFLAGS_SET=\"-g -O0\" dpkg-buildpackage -us -uc 2>&1 && touch /build.stamp)" | tee -a $LOG
  else
    chroot ${HOME}/$d sh -c "cd rspamd-${RSPAMD_VER} ; (DEBUILD_LINTIAN=no dpkg-buildpackage -us -uc 2>&1 && touch /build.stamp)" | tee -a $LOG
  fi
  
  if [ ! -f ${HOME}/$d/build.stamp ] ; then
    echo "Build failed for $d"
    exit 1
  fi

  rm -f ${HOME}/$d/build.stamp
}

build_rspamd_rpm() {
  d=$1
  _id=`git -C ${HOME}/rspamd rev-parse --short HEAD`
  echo "******* BUILD RSPAMD ${RSPAMD_VER} FOR $d ********"
  cp ${HOME}/rpm/SPECS/rspamd.spec ${HOME}/$d/${BUILD_DIR}/SPECS
  RPM_EXTRA="-DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF"
  if [ ${NO_OPT} -eq 1 ] ; then
    RPM_EXTRA="${RPM_EXTRA} -DENABLE_FULL_DEBUG=ON"
  fi
  if [ ${NO_TORCH} -eq 1 ] ; then
    RPM_EXTRA="${RPM_EXTRA} -DENABLE_TORCH=OFF"
  else
    RPM_EXTRA="${RPM_EXTRA} -DENABLE_TORCH=ON"
  fi
  if [ ${EXTRA_OPT} -eq 1 ] ; then
    RPM_EXTRA="${RPM_EXTRA} -DENABLE_OPTIMIZATION=ON"
  fi
  if [ -n "${HYPERSCAN}" ] ; then
    RPM_EXTRA="${RPM_EXTRA} -DENABLE_HYPERSCAN=ON"
  fi
  if [ -n "${STABLE}" ] ; then
    sed -e "s/^Version:[ \t]*[0-9.]*/Version: ${RSPAMD_VER}/" \
      -e "s/^Release:[\t ]*[0-9]*$/Release: ${_version}/" \
      -e "s/@@CMAKE@@/${CMAKE}/" \
      -e "s/@@EXTRA@@/${RPM_EXTRA}/" \
      < ${HOME}/$d/${BUILD_DIR}/SPECS/rspamd.spec > /tmp/.tt
  else
    sed -e "s/^Version:[ \t]*[0-9.]*/Version: ${RSPAMD_VER}/" \
      -e "s/^Release:[ \t]*[0-9]*$/Release: ${_version}.git${_id}/" \
      -e "s/@@CMAKE@@/${CMAKE}/" \
      -e "s/@@EXTRA@@/${RPM_EXTRA}/" \
      < ${HOME}/$d/${BUILD_DIR}/SPECS/rspamd.spec > /tmp/.tt
  fi

  mv /tmp/.tt ${HOME}/$d/${BUILD_DIR}/SPECS/rspamd.spec
  
  rm -f ${HOME}/$d/build.stamp
  (chroot ${HOME}/$d rpmbuild \
    --define='jobs ${JOBS}' \
    --define='BuildRoot %{_tmppath}/%{name}' \
    --define="_topdir ${BUILD_DIR}" \
    -ba ${BUILD_DIR}/SPECS/rspamd.spec 2>&1 && touch ${HOME}/$d/build.stamp) | tee -a $LOG
  if [ ! -f ${HOME}/$d/build.stamp ] ; then
    echo "Build failed for $d"
    exit 1
  fi

  rm -f ${HOME}/$d/build.stamp
}


if [ $BUILD_STAGE -eq 1 ] ; then

  if [ -n "${STABLE}" ] ; then
    export DEB_BUILD_OPTIONS="parallel=${JOBS}"
    _version="${STABLE_VER}"
  else
    export DEB_BUILD_OPTIONS="parallel=${JOBS} nostrip"
    _version=`cat ${HOME}/version || echo 0`
    if [ $# -ge 1 ] ; then
      DISTRIBS=$@
    else
      _version=$(($_version + 1))
    fi
  fi

  if [ -z "${NO_RSPAMD}" ] ; then
    if [ $DEBIAN -ne 0 ] ; then

      if [ -z "${NO_LUAJIT}" ] ; then
        if [ $BUNDLED_LUAJIT -ne 0 ] ; then
          LUAJIT_DEP=""
        else
          LUAJIT_DEP="libluajit-5.1-dev"
        fi
      else
        LUAJIT_DEP="liblua5.1-dev"
      fi

      for d in $DISTRIBS_DEB ; do
        SPECIFIC_C_COMPILER="${C_COMPILER}"
        SPECIFIC_CXX_COMPILER="${CXX_COMPILER}"
        case $d in
          debian-jessie)
            REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP}"
            RULES_SED="-e 's/--with systemd/--with systemd --parallel/' \
              -e 's/-DWANT_SYSTEMD_UNITS=ON/-DWANT_SYSTEMD_UNITS=ON -DENABLE_HYPERSCAN=ON -DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF/'"
            SPECIFIC_C_COMPILER="clang-6.0"
            SPECIFIC_CXX_COMPILER="clang++-6.0"
            ;;
          debian-stretch)
            REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP}"
            RULES_SED="-e 's/--with systemd/--with systemd --parallel/' \
              -e 's/-DWANT_SYSTEMD_UNITS=ON/-DWANT_SYSTEMD_UNITS=ON -DENABLE_HYPERSCAN=ON -DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF/'"
            ;;
          debian-sid)
            REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP}"
            RULES_SED="-e 's/--with systemd/--with systemd --parallel/' \
              -e 's/-DWANT_SYSTEMD_UNITS=ON/-DWANT_SYSTEMD_UNITS=ON -DENABLE_HYPERSCAN=ON -DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF/'"
            ;;
          ubuntu-xenial)
            REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP}"
            RULES_SED="-e 's/--with systemd/--with systemd --parallel/' \
              -e 's/-DWANT_SYSTEMD_UNITS=ON/-DWANT_SYSTEMD_UNITS=ON -DENABLE_HYPERSCAN=ON -DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF/'"
            SPECIFIC_C_COMPILER="clang-6.0"
            SPECIFIC_CXX_COMPILER="clang++-6.0"
            ;;
          ubuntu-bionic)
            SPECIFIC_C_COMPILER="clang-6.0"
            SPECIFIC_CXX_COMPILER="clang++-6.0"
            REAL_DEPS="$DEPS_DEB dh-systemd ${LUAJIT_DEP}"
            RULES_SED="-e 's/--with systemd/--with systemd --parallel/' \
              -e 's/-DWANT_SYSTEMD_UNITS=ON/-DWANT_SYSTEMD_UNITS=ON -DENABLE_HYPERSCAN=ON -DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF/'"
            ;;
          ubuntu-trusty)
            SPECIFIC_C_COMPILER="clang-6.0"
            SPECIFIC_CXX_COMPILER="clang++-6.0"
            REAL_DEPS="$DEPS_DEB ${LUAJIT_DEP}"
            RULES_SED="-e 's/--with systemd/--parallel/' \
              -e 's/-DWANT_SYSTEMD_UNITS=ON/-DWANT_SYSTEMD_UNITS=OFF -DENABLE_HYPERSCAN=ON -DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF/'"
            ;;
          ubuntu-*)
            REAL_DEPS="$DEPS_DEB ${LUAJIT_DEP}"
            RULES_SED="-e 's/--with systemd/--parallel/' \
              -e 's/-DWANT_SYSTEMD_UNITS=ON/-DWANT_SYSTEMD_UNITS=OFF -DENABLE_HYPERSCAN=ON -DHYPERSCAN_ROOT_DIR=\/opt\/hyperscan -DENABLE_FANN=OFF/'"
            ;;
          *) REAL_DEPS="$DEPS_DEB ${LUAJIT_DEP}" ;;
        esac
        build_rspamd_deb $d

        ### i386 ###
        if [ -z "${NO_I386}" ] ; then
          d="${d}-i386"
          build_rspamd_deb $d
        fi
      done

    fi # DEBIAN == 0

    if [ $RPM -ne 0 ] ; then
      for d in $DISTRIBS_RPM ; do
        HYPERSCAN=""
        CMAKE="cmake"
        SPECIFIC_C_COMPILER="${C_COMPILER}"
        SPECIFIC_CXX_COMPILER="${CXX_COMPILER}"
        DEVTOOLSET_ENABLE=""


        case $d in
          opensuse-*)
            HYPERSCAN="yes"
            ;;
          fedora-22*)
            HYPERSCAN="yes"
            ;;
          fedora-23*)
            HYPERSCAN="yes"
            ;;
          fedora-24*)
            HYPERSCAN="yes"
            ;;
          fedora-25*)
            HYPERSCAN="yes"
            ;;
          fedora-21*)
            ;;
          centos-6)
            HYPERSCAN="yes"
            DEVTOOLSET_ENABLE="/opt/rh/devtoolset-6/enable"
            ;;
          centos-7)
            HYPERSCAN="yes"
            DEVTOOLSET_ENABLE="/opt/rh/devtoolset-7/enable"
            CMAKE="cmake3"
            ;;
          *)
            YUM="yum -y"
            REAL_DEPS="$DEPS_RPM sqlite-devel ${LUAJIT_DEP}" ;;
        esac
        build_rspamd_rpm $d
      done
    fi
  fi # NO_RSPAMD != 0

  RULES_SED=""

  # Increase version
  if [ -z "${STABLE}" -a -z "${NO_INC}" ] ; then
    echo $_version > ${HOME}/version
  fi
fi

if [ ${SIGN_STAGE} -eq 1 ] ; then

  if [ -n "${STABLE}" ] ; then
    _version="${STABLE_VER}"
  else
    _version=`cat ${HOME}/version || echo 0`
  fi

  _id=`git -C ${HOME}/rspamd rev-parse --short HEAD`

  if [ $DEBIAN -ne 0 ] ; then
    rm -fr ${HOME}/repos/*
    gpg --armor --output ${HOME}/repos/gpg.key --export $KEY
    mkdir ${HOME}/repos/conf || true

    for d in $DISTRIBS_DEB ; do
      _distname=`echo $d | sed -r -e 's/ubuntu-|debian-//'`
      if [ -n "${STABLE}" ] ; then
        _pkg_ver="${RSPAMD_VER}-${_version}~${_distname}"
        _repo_descr="Apt repository for rspamd stable builds"
      else
        _pkg_ver="${RSPAMD_VER}-0~git${_version}~${_id}~${_distname}"
        _repo_descr="Apt repository for rspamd nightly builds"
      fi
      if [ -z "${NO_I386}" ] ; then
        ARCHS="source amd64 i386"
      else
        ARCHS="source amd64"
      fi
      if [ $ARM -ne 0 ] ; then
        ARCHS="${ARCHS} armhf"
      fi
      _repodir=${HOME}/repos/
      cat >> $_repodir/conf/distributions <<EOD
Origin: Rspamd
Label: Rspamd
Codename: ${_distname}
Architectures: ${ARCHS}
Components: main
Description: ${_repo_descr}
SignWith: ${KEY}

EOD
      if [ -z "${NO_RSPAMD}" ] ; then
        dpkg-sig -k $KEY --batch=1 --sign builder ${HOME}/$d/rspamd_${_pkg_ver}*.deb
        dpkg-sig -k $KEY --batch=1 --sign builder ${HOME}/$d/rspamd-dbg_${_pkg_ver}*.deb
        debsign --re-sign -k $KEY ${HOME}/$d/rspamd_${_pkg_ver}*.changes
        reprepro -b $_repodir -v --keepunreferencedfiles includedeb $_distname $d/rspamd_${_pkg_ver}_amd64.deb
        reprepro -b $_repodir -v --keepunreferencedfiles includedeb $_distname $d/rspamd-dbg_${_pkg_ver}_amd64.deb
        reprepro -b $_repodir -v --keepunreferencedfiles includedsc $_distname $d/rspamd_${_pkg_ver}.dsc
      fi

      ### i386 ###
      if [ -z "${NO_I386}" ] ; then
        d="${d}-i386"
        if [ -z "${NO_RSPAMD}" ] ; then
          dpkg-sig -k $KEY --batch=1 --sign builder ${HOME}/$d/rspamd_${_pkg_ver}*.deb
          dpkg-sig -k $KEY --batch=1 --sign builder ${HOME}/$d/rspamd-dbg_${_pkg_ver}*.deb
          debsign --re-sign -k $KEY ${HOME}/$d/rspamd_${_pkg_ver}*.changes
          reprepro -b $_repodir -v --keepunreferencedfiles includedeb $_distname $d/rspamd_${_pkg_ver}_i386.deb
          reprepro -b $_repodir -v --keepunreferencedfiles includedeb $_distname $d/rspamd-dbg_${_pkg_ver}_i386.deb
        fi
      fi

      if [ $ARM -ne 0 ] ; then
        if [ -z "${NO_RSPAMD}" ] ; then
          dpkg-sig -k $KEY --batch=1 --sign builder ${ARM}/$d/rspamd_${_pkg_ver}*.deb
          dpkg-sig -k $KEY --batch=1 --sign builder ${ARM}/$d/rspamd-dbg_${_pkg_ver}*.deb
          debsign --re-sign -k $KEY ${ARM}/$d/rspamd_${_pkg_ver}*.changes
          reprepro -b $_repodir -v --keepunreferencedfiles includedeb $_distname ${ARM}/$d/rspamd_${_pkg_ver}_armhf.deb
          reprepro -b $_repodir -v --keepunreferencedfiles includedeb $_distname ${ARM}/$d/rspamd-dbg_${_pkg_ver}_armhf.deb
        fi
      fi

      gpg -u 0x$KEY -sb $_repodir/dists/$_distname/Release && \
        mv $_repodir/dists/$_distname/Release.sig $_repodir/dists/$_distname/Release.gpg
    done
  fi # DEBIAN == 0

  if [ $RPM -ne 0 ] ; then
    rm -f ${HOME}/rpm/gpg.key || true
    ARCH="${MAIN_ARCH}"
    gpg --armor --output ${HOME}/rpm/gpg.key --export $KEY
    for d in $DISTRIBS_RPM_FULL ; do
      rm -fr ${HOME}/rpm/$d/ || true
      mkdir -p ${HOME}/rpm/$d/${ARCH} || true
    done
    for d in $DISTRIBS_RPM ; do
      cp ${HOME}/${d}/${BUILD_DIR}/RPMS/${ARCH}/*.rpm ${HOME}/rpm/$d/${ARCH}
      if [ "$d" = "centos-6" ] ; then
        cp ${HOME}/${d}/gmime*.rpm ${HOME}/rpm/$d/${ARCH}
      fi
      for p in ${HOME}/rpm/$d/${ARCH}/*.rpm ; do
        ./rpm_sign.expect $p
      done
      (cd ${HOME}/rpm/$d/${ARCH} && createrepo --compress-type gz . )

      gpg --default-key ${KEY} --detach-sign --armor \
        ${HOME}/rpm/$d/${ARCH}/repodata/repomd.xml

      if [ -n "${STABLE}" ] ; then
        cat <<EOD > ${HOME}/rpm/$d/rspamd.repo
[rspamd]
name=Rspamd stable repository
baseurl=http://rspamd.com/rpm-stable/$d/${ARCH}/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://rspamd.com/rpm/gpg.key
EOD
      else
        cat <<EOD > ${HOME}/rpm/$d/rspamd-experimental.repo
[rspamd-experimental]
name=Rspamd experimental repository
baseurl=http://rspamd.com/rpm/$d/${ARCH}/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://rspamd.com/rpm/gpg.key
EOD
      fi

    done
  fi # RPM == 0
fi

RSYNC_ARGS="-rup"

if [ $DIST -eq 0 ] ; then
  if [ ${NO_DELETE} -eq 0 ] ; then
    if [ $RPM -eq 1 -a $DEBIAN -eq 1 ] ; then
      RSYNC_ARGS="${RSYNC_ARGS} --delete --delete-before"
    fi
  fi
fi

if [ ${UPLOAD_STAGE} -eq 1 ] ; then
  if [ -z "${UPLOAD_HOST}" ] ; then
    echo "No UPLOAD_HOST specified, exiting"
    exit 1
  fi

  if [ $DEBIAN -ne 0 ] ; then
    if [ -n "${STABLE}" ] ; then
      rsync -e "ssh -i ${SSH_KEY_DEB_STABLE}" ${RSYNC_ARGS} \
        ${HOME}/repos/* ${UPLOAD_HOST}:${TARGET_DEB_STABLE}
    else
      rsync -e "ssh -i ${SSH_KEY_DEB_UNSTABLE}" ${RSYNC_ARGS} \
        ${HOME}/repos/* ${UPLOAD_HOST}:${TARGET_DEB_UNSTABLE}
    fi
  fi

  if [ $RPM -ne 0 ] ; then
    for d in $DISTRIBS_RPM ; do
      if [ -n "${STABLE}" ] ; then
        rsync -e "ssh -i ${SSH_KEY_RPM_STABLE}" ${RSYNC_ARGS} \
          ${HOME}/rpm/$d/* ${UPLOAD_HOST}:${TARGET_RPM_STABLE}/$d/
      else
        rsync -e "ssh -i ${SSH_KEY_RPM_UNSTABLE}" ${RSYNC_ARGS} \
          ${HOME}/rpm/$d/* ${UPLOAD_HOST}:${TARGET_RPM_UNSTABLE}/$d/
      fi
    done
  fi
fi
