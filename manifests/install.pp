# == Class: aerospike::install
#
# This class is called from the aerospike class to download and install an
# aerospike server
#
# == Dependencies
#
# The archive module available at:
# https://forge.puppetlabs.com/puppet/archive
#
class aerospike::install {

  include 'archive'

  # #######################################
  # Installation of aerospike server
  # #######################################
  $src = $aerospike::download_url ? {
    undef   => "http://www.aerospike.com/artifacts/aerospike-server-${aerospike::edition}/${aerospike::version}/aerospike-server-${aerospike::edition}-${aerospike::version}-${aerospike::target_os_tag}.tgz",
    default => $aerospike::download_url,
  }
  $dest = "${aerospike::download_dir}/aerospike-server-${aerospike::edition}-${aerospike::version}-${aerospike::target_os_tag}"

  archive { "${dest}.tgz":
    ensure       => present,
    source       => $src,
    username     => $aerospike::download_user,
    password     => $aerospike::download_pass,
    extract      => true,
    extract_path => $aerospike::download_dir,
    creates      => $dest,
    cleanup      => $aerospike::remove_archive,
  } ~>
  exec { 'aerospike-install-server':
    command     => "${dest}/asinstall",
    cwd         => $dest,
    refreshonly => true,
  }

  # #######################################
  # Defining the system user and group the service will be configured on
  # #######################################
  ensure_resource( 'user', $aerospike::system_user, {
      ensure  => present,
      uid     => ($aerospike::system_uid >= 0) ? {
                    true    => $aerospike::system_uid,
                    false   => undef,
                  },
      gid     => $aerospike::system_group,
      system  => true,
      shell   => '/bin/false',
      require => Group[$aerospike::system_group],
    }
  )

  ensure_resource('group', $aerospike::system_group, {
      ensure  => present,
      gid     => ($aerospike::system_gid >= 0) ? {
                    true    => $aerospike::system_gid,
                    false   => undef,
                  },
      system  => true,
    }
  )

  file { $aerospike::data_dirs:
    ensure  => directory,
    owner   => $aerospike::system_user,
    group   => $aerospike::system_group,
    mode    => '0750',
  }

  file { $aerospike::logging_dirs:
    ensure  => directory,
    owner   => $aerospike::system_user,
    # group   => defined(Group['logreader']) ? {
    #             true  => 'logreader',
    #             false => $aerospike::system_group,
    #            },
    group   => $aerospike::logging_dirs_group,
    mode    => '0750',
  }

  file { '/var/run/aerospike':
    ensure  => directory,
    owner   => $aerospike::system_user,
    # owner   => $aerospike::system_group,
    group   => $aerospike::logging_dirs_group,
    mode    => '0750',
  }

  if $aerospike::logrotate_manage_service {
    file { '/etc/logrotate.d/aerospike':
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('aerospike/logrotate-aerospike.erb'),
      notify  => undef,
    }
  }


  # #######################################
  # Installation of the management console
  # Only if asked for it.
  # #######################################
  if $aerospike::amc_install {

    # On the amc, some elements are changing depending on the os familly
    case $::osfamily {
      'Debian': {
        $amc_pkg_extension = '.all.x86_64.deb'
        $amc_pkg_provider = 'dpkg'
        $amc_extract = false
        $amc_target_archive = "${aerospike::amc_download_dir}/aerospike-amc-${aerospike::edition}-${aerospike::amc_version}${amc_pkg_extension}"
        $amc_dest = $amc_target_archive
        $bcrypt_os_packages  = ['build-essential','python-dev','libffi-dev']
      }
      'RedHat': {
        $amc_pkg_extension = '-el5.x86_64.rpm'
        $amc_pkg_provider = 'rpm'
        $amc_extract = false
        $amc_target_archive = "${aerospike::amc_download_dir}/aerospike-amc-${aerospike::edition}-${aerospike::amc_version}${amc_pkg_extension}"
        $amc_dest = $amc_target_archive
        $bcrypt_os_packages  = ['gcc', 'libffi-devel', 'python-devel']
      }
      default : {
        $amc_pkg_extension ='.tar.gz'
        $amc_pkg_provider = undef
        $amc_extract = true
        $amc_target_archive = "${aerospike::amc_download_dir}/aerospike-amc-${aerospike::edition}-${aerospike::amc_version}${amc_pkg_extension}"
        $amc_dest = "${aerospike::amc_download_dir}/aerospike-amc-${aerospike::edition}-${aerospike::amc_version}"
        $bcrypt_os_packages  = ['gcc', 'libffi-devel', 'python-devel']
      }
    }


    $amc_src = $aerospike::amc_download_url ? {
      undef => "http://www.aerospike.com/artifacts/aerospike-amc-${aerospike::edition}/${aerospike::amc_version}/aerospike-amc-${aerospike::edition}-${aerospike::amc_version}${amc_pkg_extension}",
      default => $aerospike::amc_download_url,
    }

    $os_packages  = ['python-pip', 'ansible']
    $pip_packages = ['markupsafe','paramiko','ecdsa','pycrypto']
    ensure_packages($os_packages, { ensure => installed, } )
    ensure_packages($pip_packages, {
      ensure   => installed,
      provider => 'pip',
      require  => [ Package['python-pip'], ],
    })
    ensure_packages($bcrypt_os_packages, { ensure => installed, } )
    ensure_packages('bcrypt', {
      ensure   => installed,
      provider => 'pip',
      require  => [ Package[$bcrypt_os_packages], Package['python-pip'], ],
    })
    archive { $amc_target_archive:
      ensure       => present,
      source       => $amc_src,
      username     => $aerospike::download_user,
      password     => $aerospike::download_pass,
      extract      => $amc_extract,
      extract_path => $aerospike::amc_download_dir,
      creates      => $amc_dest,
      cleanup      => $aerospike::remove_archive,

    }

    # For now only the packages that are not tarballs are installed.
    if $amc_pkg_provider != undef {
      ensure_packages("aerospike-amc-${aerospike::edition}", {
        ensure   => installed,
        provider => $amc_pkg_provider,
        source   => $amc_dest,
        require  => [ Archive[$amc_target_archive], ],
      })
    } else {
      fail('Installation of the amc via tarball not yet supported by this module.')
    }
  }
}
