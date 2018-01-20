import AlamofireImage
import Alamofire

public extension UIImage {
    
    typealias ImageLoaderCallback = (image : UIImage?) -> Void
    
    public class func fromUri(uri : String, callback : ImageLoaderCallback) {
        print("\(self.dynamicType): Downloading image at '\(uri)'...")
        Alamofire.request(.GET, uri).responseImage {
            if let img = $0.result.value {
                print("\(self.dynamicType): Image downloaded successfully (\(uri))")
                callback(image: img)
            } else {
                print("\(self.dynamicType): Image downloaded failed (\(uri))")
                callback(image: nil)
            }
        }
    }
}