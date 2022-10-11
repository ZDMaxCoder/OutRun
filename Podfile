project 'OutRun.xcodeproj'
platform :ios, '13.0'

def app_pods
  pod 'Cache'
end

def ui_pods
  pod 'SnapKit'
  pod 'Charts', '~> 4.1'
  # pod 'JTAppleCalendar'
end

def data_pods
  pod 'CoreStore', '~> 9.0'
  pod 'CoreGPX'
end

def rx_pods
  pod 'RxSwift'
  pod 'RxCocoa'
end

def amap_pods
  pod 'AMapLocation-NO-IDFA'
end

target 'OutRun' do
  use_frameworks!

  app_pods
  ui_pods
  rx_pods
  data_pods
  amap_pods

  target 'UnitTests' do
    inherit! :search_paths
  end

end
