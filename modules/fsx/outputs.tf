
output "fs_openzfs_id" {
  description = "FSx OpenZFS file system ID"
  value       = aws_fsx_openzfs_file_system.fsxz.id
}

output "fs_openzfs_dns" {
  description = "FSx OpenZFS file system DNS"
  value       = aws_fsx_openzfs_file_system.fsxz.dns_name
}

output "sw_vol_id" {
  description = "FSx OpenZFS sw volume ID"
  value       = aws_fsx_openzfs_volume.sw.id
}

output "home_vol_id" {
  description = "FSx OpenZFS home volume ID"
  value       = aws_fsx_openzfs_volume.home.id
}

output "fs_lustre_id" {
  description = "FSx Lustre file system ID"
  value       = aws_fsx_lustre_file_system.fsxl.id
}

output "fs_lustre_dns" {
  description = "FSx Lustre file system DNS"
  value       = aws_fsx_lustre_file_system.fsxl.dns_name
}

output "fs_lustre_mnt" {
  description = "FSx Lustre file system mount name"
  value       = aws_fsx_lustre_file_system.fsxl.mount_name
}

output "fs_lustre_sg" {
  description = "FSx Lustre file system security group"
  value       = aws_security_group.fsxl.id
}

output "fs_zfs_sg" {
  description = "FSx OpenZFS file system security group"
  value       = aws_security_group.zfs.id
}

output "fs_lustre_dra_path" {
  description = "Lustre mount path linked to the benchmarking S3 bucket via DRA."
  value       = aws_fsx_data_repository_association.results.file_system_path
}
