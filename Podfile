platform :ios, '15.0'
use_frameworks!

target 'Frotz' do
    pod 'ObjectiveDropboxOfficial'
end

# Match the app's minimum OS, including pods that still declare an older one.
# Xcode 27 rejects those older deployment targets before compilation starts.
post_install do |installer|
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            minimum = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || '0'
            if Gem::Version.new(minimum) < Gem::Version.new('15.0')
                config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
            end
        end
    end
end
